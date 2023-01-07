-- CREATE DATABASE "GenealogistService";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- Czyszczenie bazy danych

DROP TABLE IF EXISTS Users CASCADE;

DROP TABLE IF EXISTS People CASCADE;

DROP TABLE IF EXISTS Couples CASCADE;

DROP TABLE IF EXISTS Trees;

DROP TABLE IF EXISTS Registrations CASCADE;

DROP TABLE IF EXISTS Preferences;

DROP TABLE IF EXISTS "Subscription Types" CASCADE;

DROP TABLE IF EXISTS Subscribers CASCADE;

DROP TABLE IF EXISTS "Payment Methods" CASCADE;

DROP TABLE IF EXISTS Payments;

DROP TABLE IF EXISTS Tokens;


-- Tworzenie tabel

CREATE TABLE IF NOT EXISTS Users (
	ID uuid PRIMARY KEY DEFAULT uuid_generate_v4 (),
	username text UNIQUE NOT NULL,
	email text UNIQUE NOT NULL,
	password text NOT NULL
);

CREATE TABLE IF NOT EXISTS People (
	ID serial PRIMARY KEY,
	ownerID uuid REFERENCES Users (ID) NOT NULL,
	firstName text NOT NULL,
	lastName text NOT NULL,
	additionalName text,
	birthName text,
	dateOfBirth date,
	dateOfDeath date,
	coupleID int,
	parentCoupleID int
);

CREATE TABLE IF NOT EXISTS Couples (
	ID serial UNIQUE NOT NULL,
	firstPersonID int REFERENCES People (ID) NOT NULL,
	secondPersonID int REFERENCES People (ID) NOT NULL,
	PRIMARY KEY (firstPersonID, secondPersonID),
	CHECK (firstPersonID != secondPersonID)
);

ALTER TABLE People
	ADD CONSTRAINT fk_couple FOREIGN KEY (coupleID) REFERENCES Couples (ID),
	ADD CONSTRAINT fk_parentCouple FOREIGN KEY (parentCoupleID) REFERENCES Couples (ID);

CREATE TABLE IF NOT EXISTS Trees (
	ID serial UNIQUE NOT NULL,
	ownerID uuid REFERENCES Users (ID),
	rootCoupleID int REFERENCES Couples (ID),
	PRIMARY KEY (ownerID, rootCoupleID)
);

CREATE TABLE IF NOT EXISTS Registrations (
	userID uuid REFERENCES Users (ID) NOT NULL,
	registrationDate timestamp with time zone NOT NULL
);

CREATE TABLE IF NOT EXISTS Preferences (
	userID uuid REFERENCES Users (ID) NOT NULL,
	newsletter boolean,
	showDates boolean,
	exportInDarkTheme boolean,
	useBoldFonts boolean
);

CREATE TABLE IF NOT EXISTS "Subscription Types" (
	type text PRIMARY KEY,
	price money NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS Subscribers (
	userID uuid REFERENCES Users (ID),
	startDate timestamp NOT NULL,
	endDate timestamp NOT NULL,
	subscriptionType text REFERENCES "Subscription Types" (type) NOT NULL,
	CHECK (startDate < endDate),
	PRIMARY KEY (userID, startDate)
);

CREATE TABLE IF NOT EXISTS "Payment Methods" (
	method text PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS Payments (
	userID uuid REFERENCES Users (ID) NOT NULL,
	method text REFERENCES "Payment Methods" (method) NOT NULL,
	subscriptionType text REFERENCES "Subscription Types" (type) NOT NULL,
	succeded boolean NOT NULL,
	errorMessage text,
	total money NOT NULL,
	timestamp timestamp NOT NULL,
	PRIMARY KEY (userID, timestamp)
);

CREATE TABLE IF NOT EXISTS Tokens (
	userID uuid PRIMARY KEY REFERENCES Users (ID),
	token text NOT NULL,
	renewToken text NOT NULL,
	deleteToken text NOT NULL,
	expires timestamp NOT NULL
);


-- Wyzwalacze i ich procedury

CREATE OR REPLACE FUNCTION check_couple_trigger ()
	RETURNS TRIGGER
	AS $$
BEGIN
	IF EXISTS (
		SELECT 1
		FROM Couples AS C
		WHERE NEW.firstPersonID = C.secondPersonID
			AND NEW.secondPersonID = C.firstPersonID) THEN
	RAISE 'Duplicate couple: (%, %) already exists', NEW.secondPersonID, NEW.firstPersonID
	USING ERRCODE = 'unique_violation';
	 ELSIF (
				SELECT ownerID FROM People
				WHERE ID = NEW.firstPersonID
			)
		!=
			(
				SELECT ownerID FROM People
				WHERE	ID = NEW.secondPersonID
			) THEN
				RAISE 'Cannot couple people from different owners: "%" and "%"', (
					SELECT ownerID FROM People
					WHERE	ID = NEW.firstPersonID), (
					SELECT ownerID FROM	People
					WHERE	ID = NEW.secondPersonID);
	END IF;
	RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION add_couple_trigger ()
	RETURNS TRIGGER
	AS $$
BEGIN
	UPDATE
		People AS P
	SET
		coupleID = NEW.ID
	WHERE
		P.ID IN (NEW.firstPersonID, NEW.secondPersonID);
	RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION add_user_trigger ()
	RETURNS TRIGGER
	AS $$
BEGIN
	INSERT INTO Registrations (userID, registrationDate)
		VALUES (NEW.ID, LOCALTIMESTAMP);
	RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION check_tree_trigger ()
	RETURNS TRIGGER
	AS $$
BEGIN
	IF EXISTS (
		SELECT
			1
		FROM
			Couples AS C
			JOIN People AS P ON P.coupleID = C.ID
		WHERE
			C.ID = NEW.rootCoupleID
			AND P.ownerID != NEW.ownerID) THEN
			RAISE 'Cannot create a tree from persons owned by another user';
	END IF;
	RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION save_payment_trigger ()
	RETURNS TRIGGER
	AS $$
BEGIN
	IF NEW.succeded = TRUE THEN
		IF EXISTS (
			SELECT
				1
			FROM
				Subscribers AS S
			WHERE
				NEW.userID = S.userID
				AND NEW.subscriptionType = S.subscriptionType
				AND endDate >= NEW.timestamp) THEN
		UPDATE
			Subscribers AS S
		SET
			endDate = endDate + interval '1 month'
		WHERE
			NEW.userID = S.userID
			AND NEW.subscriptionType = S.subscriptionType
			AND endDate >= NEW.timestamp;
	ELSE
		INSERT INTO Subscribers
			VALUES (NEW.userID, NEW.timestamp, NEW.timestamp + interval '1 month', NEW.subscriptionType);
	END IF;
END IF;
	RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;


-- Wyzwalacze

CREATE TRIGGER add_user
	AFTER INSERT ON Users
	REFERENCING NEW TABLE AS inserted
	FOR EACH ROW
	EXECUTE FUNCTION add_user_trigger ();

CREATE TRIGGER check_couple
	BEFORE INSERT ON Couples
	FOR EACH ROW
	-- Check if couple already exists (prevent (1,2) (2,1))
	EXECUTE FUNCTION check_couple_trigger ();
	
CREATE TRIGGER add_couple
	AFTER INSERT ON Couples
	FOR EACH ROW
	EXECUTE FUNCTION add_couple_trigger ();
	
CREATE TRIGGER add_tree
	BEFORE INSERT ON Trees
	FOR EACH ROW
	EXECUTE FUNCTION check_tree_trigger ();
	
CREATE TRIGGER save_payment
	AFTER INSERT ON Payments
	FOR EACH ROW
	EXECUTE FUNCTION save_payment_trigger ();


-- Funkcje

CREATE OR REPLACE FUNCTION get_couple_parent_couple_id (pcoupleID integer)
	RETURNS int
	AS $$
	SELECT
		CASE WHEN P1.parentCoupleID IS NULL THEN
			P2.parentCoupleID
		WHEN P2.parentCoupleID IS NULL THEN
			P1.parentCoupleID
		ELSE
			NULL
		END
	FROM
		Couples AS Co
		JOIN People AS P1 ON P1.ID = Co.firstPersonID
		JOIN People AS P2 ON P2.ID = Co.secondPersonID
	WHERE
		Co.ID = pcoupleID
$$
LANGUAGE SQL;

CREATE OR REPLACE FUNCTION get_root_couple_id (coupleID integer)
	RETURNS int
	AS $$
DECLARE
	curr int;
	nextCouple int;
BEGIN
	IF coupleID IS NULL THEN
		RAISE null_value_not_allowed;
	END IF;
	curr := coupleID;
	LOOP
		nextCouple := get_couple_parent_couple_id (curr);
		IF nextCouple IS NULL THEN
			RETURN curr;
		ELSE
			curr := nextCouple;
		END IF;
	END LOOP;
END;
$$
LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION get_person_age (personID int)
	RETURNS interval
	AS $$
	SELECT
		age(dateofdeath, dateofbirth) AS age
	FROM
		People
	WHERE
		ID = personID;
$$
LANGUAGE SQL;


-- Widoki

CREATE OR REPLACE RECURSIVE VIEW display_ancestors_couple (OwnerID, TreeID, Parents, Couple, Path) AS
SELECT
	P1.ownerID AS OwnerID,
	T.ID AS TreeID,
	get_couple_parent_couple_id (C.ID) AS Parents,
	C.ID AS Couple,
	(P1.firstname || ' ' || P1.lastname || ' & ' || P2.firstname || ' ' || P2.lastname) AS Path
FROM
	Couples AS C
	LEFT JOIN People AS P1 ON P1.ID = firstPersonID
	LEFT JOIN People AS P2 ON P2.ID = secondPersonID
	LEFT JOIN Trees AS T ON T.rootCoupleID = C.ID
WHERE
	get_couple_parent_couple_id (C.ID) IS NULL
UNION ALL
SELECT
	P3.ownerID AS OwnerID,
	DT.TreeID AS TreeID,
	DT.Couple AS Parents,
	Co.ID AS Couple,
	(DT.Path || ' -> ' || P3.firstname || ' ' || P3.lastname || ' & ' || P4.firstname || ' ' || P4.lastname) AS Path
FROM
	Couples AS Co
	JOIN display_ancestors_couple AS DT ON get_couple_parent_couple_id (Co.ID) = DT.Couple
	LEFT JOIN People AS P3 ON P3.ID = firstPersonID
	LEFT JOIN People AS P4 ON P4.ID = secondPersonID;

CREATE OR REPLACE VIEW display_ancestors AS
SELECT
	DAC.ownerID,
	DAC.treeID,
	DAC.Path || ' -> ' || P.firstname || ' ' || P.lastname AS Paths
FROM
	display_ancestors_couple AS DAC
	JOIN People AS P ON P.parentCoupleID = DAC.Couple
UNION ALL
SELECT
	DAC.ownerID,
	DAC.treeID,
	DAC.Path AS Paths
FROM
	display_ancestors_couple AS DAC;
	
CREATE OR REPLACE VIEW current_subscribers AS
SELECT
	*
FROM
	Subscribers
WHERE
	startDate <= LOCALTIMESTAMP
	AND LOCALTIMESTAMP <= endDate;

-- Wypelnienie bazy danych

INSERT INTO Users (username, email, PASSWORD)
	VALUES ('test1', 'test1@gmail.com', crypt('test1', gen_salt('bf'))),
		('test2', 'test2@gmail.com', crypt('test2', gen_salt('bf'))),
		('test3', 'test3@gmail.com', crypt('test3', gen_salt('bf'))),
		('test4', 'test4@gmail.com', crypt('test4', gen_salt('bf')));
	
INSERT INTO People (firstName, lastName, dateOfBirth, dateOfDeath, ownerID)
	VALUES ('Andrzej', 'Matiasz', make_date(1900, 1, 1), make_date(1911, 1, 1), (SELECT id FROM Users WHERE username = 'test1')),
	('Maciej', 'Jarewicz', make_date(1901, 1, 1), make_date(1920, 1, 1), (SELECT id FROM Users WHERE username = 'test1')),
	
	('Adam', 'Krzykiewski', make_date(1903, 1, 1), make_date(1933, 1, 1), (SELECT id FROM Users WHERE username = 'test1')),
	('Lorenza', 'Ubes', make_date(1947, 1, 1), make_date(1993, 1, 1), (SELECT id FROM Users WHERE username = 'test1')),
	
	('Henryk', 'Kapacz', make_date(1911, 1, 1), make_date(1922, 1, 1), (SELECT id FROM Users WHERE username = 'test1')),
	('Agata', 'Lomper', make_date(1923, 1, 1), make_date(1960, 1, 1), (SELECT id FROM Users WHERE username = 'test1')),
	
	('Bartosz', 'Fano', make_date(1932, 1, 1), make_date(2003, 1, 1), (SELECT id FROM Users WHERE username = 'test1')),
	('Sandra', 'Eppler', make_date(1983, 1, 1), make_date(2022, 1, 1), (SELECT id FROM Users WHERE username = 'test1')),
	
	('Marianna', 'Kuźmir', make_date(1944, 1, 1), make_date(2003, 1, 1), (SELECT id FROM Users WHERE username = 'test2')),
	('Kacper', 'Komrat', make_date(1973, 1, 1), make_date(2022, 1, 1), (SELECT id FROM Users WHERE username = 'test2'));

INSERT INTO Couples (firstPersonID, secondPersonID)
	VALUES (1, 2), (3, 4), (5, 6), (7, 8), (9, 10);

-- Błąd	
--INSERT INTO Couples (firstPersonID, secondPersonID)
--	VALUES (1, 9);

UPDATE People 
	SET parentCoupleID = 1
	WHERE firstName IN ('Adam');
	
UPDATE People
	SET parentCoupleID = 2
	WHERE firstName IN ('Agata', 'Sandra');

INSERT INTO Trees (ownerID, rootCoupleID)
	VALUES (
		(
			SELECT id FROM Users
			WHERE username = 'test1'
		), 1),
	(
		(
			SELECT id
			FROM Users
			WHERE username = 'test2'
		), 5);

INSERT INTO "Payment Methods"
	VALUES ('Credit card'), ('Paypal'), ('Skrill'), ('Apple Pay'), ('Google Pay');
	
INSERT INTO "Subscription Types"
	VALUES ('Basic', 0.99), ('Premium', 2.99), ('Business', 9.99);
	
INSERT INTO Payments
	VALUES ((
			SELECT id FROM Users
			WHERE username = 'test1'
		), 'Paypal', 'Basic', true, NULL, 0.99, make_date(1999, 1, 21)),
		((
			SELECT id FROM Users
			WHERE username = 'test4'
		), 'Google Pay', 'Premium', true, NULL, 2.99, make_date(2002, 1, 21)),
		((
			SELECT id FROM Users
			WHERE username = 'test1'
		), 'Apple Pay', 'Basic', true, NULL, 0.99, make_date(1999, 2, 20)),
		((
			SELECT id FROM Users
			WHERE username = 'test1'
		), 'Credit card', 'Business', false, 'Zbyt niskie saldo', 9.99, make_date(1999, 4, 21)),
		((
			SELECT id FROM Users
			WHERE username = 'test1'
		), 'Credit card', 'Business', true, NULL, 9.99, make_date(1999, 4, 21) + interval '1 minute'),
		((
			SELECT id FROM Users
			WHERE username = 'test1'
		), 'Credit card', 'Premium', true, NULL, 2.99, make_date(1999, 4, 23)),
		((
			SELECT id FROM Users
			WHERE username = 'test1'
		), 'Credit card', 'Premium', true, NULL, 2.99, make_date(2023, 1, 2));
		
		
-- preferences dorobic		
		

-- Wypisanie

SELECT * FROM Subscribers;
SELECT * FROM current_subscribers;
SELECT * FROM PAYMENTS;

SELECT
	*
FROM
	display_ancestors;

SELECT
	*
FROM
	display_ancestors_couple;
--WHERE Couple = 3;
		
SELECT get_couple_parent_couple_id (3);

SELECT
	get_root_couple_id (3);

SELECT
	*
FROM
	Users;
	
SELECT
	*
FROM
	People;
	
SELECT
	*
FROM
	Couples;

SELECT
	*
FROM
	Trees;
