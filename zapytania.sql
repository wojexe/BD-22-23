-- Wypelnienie bazy danych

INSERT INTO Users (username, email, password)
    VALUES ('test1', 'test1@gmail.com', 'testPass1'),
        ('test2', 'test2@gmail.com', 'testPass2'),
        ('test3', 'test3@gmail.com', 'testPass3'),  
        ('test4', 'test4@gmail.com', 'testPass4');

DO $$
DECLARE test1ID uuid;
DECLARE test2ID uuid;
BEGIN

test1ID := (SELECT id FROM Users WHERE username = 'test1');
test2ID := (SELECT id FROM Users WHERE username = 'test2');

INSERT INTO Trees (name, ownerID)
    VALUES ('test1s tree', test1ID),
           ('test2s tree', test2ID);


INSERT INTO People (firstName, lastName, dateOfBirth, dateOfDeath, ownerID, treeID)
   VALUES ('Andrzej', 'Matiasz', make_date(1900, 1, 1), make_date(1911, 1, 1), test1ID, 1),
   ('Maciej', 'Jarewicz', make_date(1901, 1, 1), make_date(1920, 1, 1), test1ID, 1),
   
   ('Adam', 'Krzykiewski', make_date(1903, 1, 1), make_date(1933, 1, 1), test1ID, 1),
   ('Lorenza', 'Ubes', make_date(1947, 1, 1), make_date(1993, 1, 1), test1ID, 1),
   
   ('Henryk', 'Kapacz', make_date(1911, 1, 1), make_date(1922, 1, 1), test1ID, 1),
   ('Agata', 'Lomper', make_date(1923, 1, 1), make_date(1960, 1, 1), test1ID, 1),
   
   ('Bartosz', 'Fano', make_date(1932, 1, 1), make_date(2003, 1, 1), test1ID, 1),
   ('Sandra', 'Eppler', make_date(1983, 1, 1), make_date(2022, 1, 1), test1ID, 1),
   
   ('Marianna', 'Kuźmir', make_date(1944, 1, 1), make_date(2003, 1, 1), test2ID, 2),
   ('Kacper', 'Komrat', make_date(1973, 1, 1), make_date(2022, 1, 1), test2ID, 2);
   
END;
$$ LANGUAGE PLPGSQL;

INSERT INTO Couples (firstPersonID, secondPersonID)
   VALUES (1, 2), (3, 4), (5, 6), (7, 8), (9, 10);

-- BŁĄD	
--INSERT INTO Couples (firstPersonID, secondPersonID)
--	VALUES (1, 9);

-- BŁĄD	
--INSERT INTO Couples (firstPersonID, secondPersonID)
--	VALUES (1, 2);

-- BŁĄD	
--INSERT INTO Couples (firstPersonID, secondPersonID)
--	VALUES (2, 1);


UPDATE People 
   SET parentCoupleID = 1
   WHERE firstName IN ('Adam');


UPDATE People
   SET parentCoupleID = 2
   WHERE firstName IN ('Agata', 'Sandra');


--DELETE FROM Users WHERE username = 'test1';
--DELETE FROM Trees WHERE id = 1;
--DELETE FROM Couples WHERE id = 2;


INSERT INTO "Payment Methods"
    VALUES ('Credit card'), ('Paypal'), ('Skrill'), ('Apple Pay'), ('Google Pay');


INSERT INTO "Subscription Types"
    VALUES ('Basic', 0.99), ('Premium', 2.99), ('Business', 9.99);


INSERT INTO Payments
    VALUES ((
            SELECT id FROM Users
            WHERE username = 'test1'
        ), 'Paypal', 'Basic', NULL, 0.99, make_date(1999, 1, 21)),
        ((
            SELECT id FROM Users
            WHERE username = 'test4'
        ), 'Google Pay', 'Premium', NULL, 2.99, make_date(2002, 1, 21)),
        ((
            SELECT id FROM Users
            WHERE username = 'test1'
        ), 'Apple Pay', 'Basic', NULL, 0.99, make_date(1999, 2, 20)),
        ((
            SELECT id FROM Users
            WHERE username = 'test1'
        ), 'Credit card', 'Business', 'Zbyt niskie saldo', 9.99, make_date(1999, 4, 21)),
        ((
            SELECT id FROM Users
            WHERE username = 'test1'
        ), 'Credit card', 'Business', NULL, 9.99, make_date(1999, 4, 21) + interval '1 minute'),
        ((
            SELECT id FROM Users
            WHERE username = 'test1'
        ), 'Credit card', 'Premium', NULL, 2.99, make_date(1999, 4, 23)),
        ((
            SELECT id FROM Users
            WHERE username = 'test1'
        ), 'Credit card', 'Basic', NULL, 0.99, make_date(2023, 1, 10)),
        ((
            SELECT id FROM Users
            WHERE username = 'test2'
        ), 'Credit card', 'Premium', NULL, 2.99, make_date(2023, 1, 10)),
        ((
            SELECT id FROM Users
            WHERE username = 'test3'
        ), 'Credit card', 'Business', NULL, 9.99, make_date(2023, 1, 10));


INSERT INTO Preferences
    VALUES ((
            SELECT id FROM Users
            WHERE username = 'test1'
        ), true, true, false, false),
        ((
            SELECT id FROM Users
            WHERE username = 'test2'
        ), true, true, true, false),
        ((
            SELECT id FROM Users
            WHERE username = 'test3'
        ), true, true, true, true);
        
-- BŁĄD
-- INSERT INTO Preferences
--     VALUES ((
--             SELECT id FROM Users
--             WHERE username = 'test1'
--         ), true, true, true, false);

-- BŁĄD
-- INSERT INTO Preferences
--     VALUES ((
--             SELECT id FROM Users
--             WHERE username = 'test1'
--         ), true, true, true, true);


-- Operacje na tokenie:
--SELECT token_request(bind_token('<id użytkownika>', '<token>'), <'access' | 'renew' | 'delete'>,  <appName >);

SELECT
    token_request (bind_token((
        SELECT
            id
        FROM Users
        WHERE
            username = 'test1'), ''), 'create', 'Google Docs');


SELECT get_payments_between(make_date(1999, 1, 19), make_date(1999, 4, 23) - interval '1 hour');

SELECT * FROM Subscribers;
SELECT * FROM current_subscribers;
SELECT * FROM Payments;

SELECT
    *
FROM
    display_ancestors;

SELECT
    *
FROM
    display_ancestors_couple;
--WHERE Couple = 3;
