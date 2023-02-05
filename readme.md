# Projekt zaliczeniowy - BD 22/23

#### Baza danych serwisu internetowego pozwalającego użytkownikom tworzyć drzewa genealogiczne

##### Wojciech Sierotowicz

---

Projekt jest implementacją bazy danych serwisu internetowego oferującego tworzenie, przechowywanie i edycję drzew genealogicznych rodzin. Użytkownicy mogą tworzyć własne konta, które są zapisywane w bazie danych oraz łączone z odpowiednimi drzewami przez nich tworzonymi. Każdy użytkownik ma możliwość wykupienia subskrypcji, dającej dostęp do pewnych dodatkowych udogodnień.

Baza danych jest przeznaczona do wykorzystania przez serwer back-endowy, który powinien pełnić rolę pośrednika pomiędzy aplikacją kliencką, a samą bazą danych. Owe pośredniczenie winno   polegać na oferowaniu dostępu do bazy danych poprzez udostępnianie REST API dla klienta.

## Strategia pielęgnacji

Serwis internetowy powinien zabezpieczać się przed wszelką utratą danych użytkowników, gdyż ich utrata mogłaby odbić się sporym echem, szczególnie w przypadku gdyby serwis zyskał sporą popularność, gdzie straty w danych okazałyby się spore. Dlatego też, zalecane jest, by raz na jakiś czas (np. co miesiąc) wykonać pełną kopię zapasową danych.

W bazie danych PostgreSQL istnieje narzędzie umożliwiające wykonywanie *Ciągłej Archiwizacji*, umożliwiającej *Point-in-Time recovery*, czyli mechanizm archiwizujący dane z bazy, w taki sposób, by można było, po ewentualnym błędzie lub awarii, przywrócić ją do nieodległego czasowo, poprawnego stanu.

## Diagram ER

![Diagram ER Bazy Danych](./Diagram%20ER.png "Diagram ER Bazy Danych")

## Schemat bazy danych

![Schemat bazy danych](./Schemat%20Bazy%20Danych.png "Schemat bazy danych")

## Tabele

| Nazwa tabeli | Przechowywane dane |
| --- | --- |
| Users | Użytkownicy serwisu |
| Subscribers | Subskrybenci serwisu - dane o czasie, w którym posiadali pewien rodzaj subskrypcji |
| Subscription Types | Rodzaje subskrypcji |
| Payments | Historia płatności dokonanych przez użytkowników |
| Payment Methods | Metody płatności |
| Preferences | Ustawienia użytkownika - niektóre wymagające subskrypcji |
| Tokens | Klucze dostępu, utworzone przez użytkowników, w celu programatycznego dostępu do serwisu (API) |
| Registrations | Historia rejestracji użytkowników |
| People | Osoby wpisane do serwisu - mogą być dodane do drzew |
| Couples | Związki pomiędzy osobami dodanymi do serwisu |
| Trees | Nazwa drzewa, korzeń oraz identyfikator wraz z twórcą |

## Widoki

##### Widok rekurencyjny wyświetlający wszystkie ścieżki od korzenia drzewa, do najmłodszych związków
###### Rekurencyjny widok, to widok z niejawnym CTE

```sql
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
```

##### Widok "doklejający" dzieci poszczególnych par do rezultatów powyższego widoku

```sql
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
```

##### Widok na aktywnych subskrybentów serwisu

```sql
CREATE OR REPLACE VIEW current_subscribers AS
SELECT
    *
FROM
    Subscribers
WHERE
    startDate <= LOCALTIMESTAMP
    AND LOCALTIMESTAMP <= endDate;
```

## Procedury składowane

##### Procedura składowana zwracająca ID związku, którego dzieckiem jest jedna z osób w zadanej argumentem parze

```sql
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
```

##### Procedura składowana zwracająca wiek danej osoby znajdującej się w drzewie genealogicznym w formacie daty

```sql
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
```

##### Procedura składowana zwracająca wszystkie osoby o nazwisku takim samym, co osoba, której ID podano w argumencie

```sql
CREATE OR REPLACE FUNCTION get_people_with_lastname_same_as (personID int)
    RETURNS SETOF People
    AS $$
        SELECT
            *
        FROM
            People AS P
        WHERE
            P.lastName = (SELECT Pe.lastName 
                          FROM People AS Pe 
                          WHERE Pe.ID = personID);
$$
LANGUAGE SQL;
```

##### Procedura składowana zwracająca wszystkich nowych subskrybentów serwisu z okresu zadanego argumentami

```sql
CREATE OR REPLACE FUNCTION get_new_subscribers (pstartTime timestamp, pendTime timestamp)
    RETURNS SETOF Subscribers
    AS $$
    SELECT
        *
    FROM
        Subscribers AS S
    WHERE
        pstartTime <= S.startDate
        AND S.startDate <= pendTime;
$$
LANGUAGE SQL;
```

##### Procedura składowana zwracająca wszystkich utraconych subskrybentów serwisu z okresu zadanego argumentami

```sql
CREATE OR REPLACE FUNCTION get_lost_subscribers (pstartTime timestamp, pendTime timestamp)
    RETURNS SETOF Subscribers
    AS $$
    SELECT
        *
    FROM
        Subscribers AS S
    WHERE
        pstartTime <= S.endDate
        AND S.endDate <= pendTime;
$$
LANGUAGE SQL;
```

##### Procedura składowana zwracająca wszystkie płatności, które odbyły się w zadanym argumentami przedziale czasowym

```sql
CREATE OR REPLACE FUNCTION get_payments_between (pstartTime timestamp, pendTime timestamp)
 RETURNS SETOF Payments
 AS $$
  SELECT
      *
  FROM
      Payments as P
  WHERE
      pstartTime <= "timestamp"
      AND "timestamp" <= pendTime;
$$
LANGUAGE SQL;
```

## Funkcje

##### Funkcja zwracająca parę będącą korzeniem drzewa

```sql
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
```

##### Funkcja zwracająca unikalne ID użytkownika o nazwie zadanej argumentem

```sql
CREATE OR REPLACE FUNCTION get_uuid (pusername text)
  RETURNS TABLE (
    uuid uuid,
    uuid_send text
  )
  AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM Users AS U
    WHERE U.username = pusername) THEN
    RAISE 'Provided user does not exist.';
  END IF;
  
  RETURN QUERY
    SELECT ID, encode(uuid_send(ID), 'base64')
    FROM Users AS U
    WHERE U.username = pusername;
END;
$$
LANGUAGE PLPGSQL;
```

##### Funkcja generująca token, będący zaszyfrowanym napisem

```sql
CREATE OR REPLACE FUNCTION generate_token (string text)
    RETURNS text
    AS $$
BEGIN
    RETURN crypt(string, gen_salt('md5'));
END;
$$
LANGUAGE PLPGSQL;
```

##### Funkcja dopisująca zakodowane ID użytkownika do tokenu (lub nawet dowolnego napisu)

```sql
CREATE OR REPLACE FUNCTION bind_token (userID uuid, token text)
    RETURNS text
    AS $$
BEGIN
    RETURN encode(uuid_send(userID), 'base64') || ':' || token;
END;
$$
LANGUAGE PLPGSQL;
```

##### Funkcja rozczytująca zakodowany powyższymi metodami token

```sql
CREATE OR REPLACE FUNCTION decode_token (token text)
    RETURNS TABLE (
        userID uuid,
        hash text
    )
    AS $$
DECLARE
    colonPos int;
    userID uuid;
    hash text;
BEGIN
    colonPos := position(':' IN token);
    userID := substring(decode(substring(token FOR colonPos - 1), 'base64')::text FROM 3)::uuid;
    hash := substring(token FROM colonPos + 1 FOR octet_length(token));
    RETURN QUERY
    SELECT
        userID,
        hash;
END;
$$
LANGUAGE PLPGSQL;
```

##### Funkcja przyznająca użytkownikowi token dostępu do serwisu

```sql
CREATE OR REPLACE FUNCTION access_request (puserID uuid, appName text)
    RETURNS TABLE (
        userID uuid,
        message text,
        token text,
        renewToken text,
        deleteToken text,
        expires timestamp
    )
    AS $$
DECLARE
    tempToken text;
BEGIN
    tempToken := generate_token ('access' || appName);
    INSERT INTO Tokens(userID, applicationName, token, renewToken, deleteToken, expires)
    VALUES (puserID, appName,
                    tempToken,
                    generate_token ('renew' || appName),
                    generate_token ('delete' || appName),
                    LOCALTIMESTAMP + interval '1 month');
            
    RETURN QUERY
        SELECT puserID,
                     'New tokens generated.',
                      bind_token(puserID, T.token),
                   bind_token(puserID, T.renewToken),
                   bind_token(puserID, T.deleteToken),
                   LOCALTIMESTAMP + interval '1 month'
        FROM Tokens AS T
        WHERE T.userID = puserID
            AND T.token = tempToken
            AND T.expires > LOCALTIMESTAMP
        ORDER BY T.expires DESC;
END;
$$
LANGUAGE PLPGSQL;
```

##### Funkcja odnawiająca token użytkownika serwisu

```sql
CREATE OR REPLACE FUNCTION renew_request (puserID uuid, tokenData text, appName text)
    RETURNS TABLE (
        userID uuid,
        message text,
        token text,
        renewToken text,
        deleteToken text,
        expires timestamp
    )
    AS $$
DECLARE
    tempToken text;
BEGIN
    tempToken := generate_token ('renew' || (SELECT applicationName FROM Tokens AS T
                                             WHERE T.userID = puserID
                                                 AND T.renewToken = tokenData 
                                                 AND T.expires > LOCALTIMESTAMP));

    UPDATE Tokens AS T
    SET (renewToken, expires) = 
        (tempToken, LOCALTIMESTAMP + interval '1 month')
    WHERE T.renewToken = tokenData AND T.expires > LOCALTIMESTAMP;

    RETURN QUERY
        SELECT puserID,
         'The token is renewed.',
         NULL,
         bind_token(puserID, T.renewToken),
         NULL,
         LOCALTIMESTAMP + interval '1 month'
        FROM Tokens AS T
        WHERE T.userID = puserID
            AND T.renewToken = tempToken
        ORDER BY T.expires DESC;
END;
$$
LANGUAGE PLPGSQL;
```

##### Funkcja obsługująca przydzielanie tokenów dla użytkowników

```sql
CREATE OR REPLACE FUNCTION token_request (providedToken text, requestType TokenRequestType, appName text)
    RETURNS TABLE (
        userID uuid,
        message text,
        token text,
        renewToken text,
        deleteToken text,
        expires timestamp
    )
    AS $$
DECLARE
     puserID uuid;
     tokenData text;
     tempToken text;
BEGIN
    SELECT DT.userID, DT.hash INTO puserID, tokenData FROM decode_token(providedToken) AS DT;

    CASE requestType
    WHEN 'create' THEN
        IF (
            SELECT
                count(T.userID)
            FROM
                Tokens AS T
            WHERE 
                T.userID = puserID
                AND T.expires > LOCALTIMESTAMP) > 20 THEN
            RAISE 'You can have at most 20 active tokens at the same time.'
            USING HINT = 'Delete some of your tokens.';
        ELSE
            RETURN QUERY SELECT * FROM access_request(puserID, appName);
        END IF;
    WHEN 'renew' THEN
        IF NOT EXISTS (SELECT 1 FROM Tokens AS T
                                        WHERE T.userID = puserID
                                            AND T.renewToken = tokenData
                                            AND T.expires > LOCALTIMESTAMP) THEN
            RAISE 'The token you have provided is not a valid token.'
            USING HINT = 'It may have expired.';
        ELSE
            RETURN QUERY SELECT * FROM renew_request(puserID, tokenData, appName);
        END IF;
    WHEN 'delete' THEN
        IF NOT EXISTS (SELECT 1 FROM Tokens AS T
                                        WHERE T.userID = puserID 
                                            AND T.deleteToken = tokenData
                                            AND T.expires > LOCALTIMESTAMP) THEN
            RAISE 'The token you have provided is not a valid token.'
            USING HINT = 'It may have expired.';
        ELSE
            DELETE FROM Tokens AS T
            WHERE T.deleteToken = tokenData AND T.expires > LOCALTIMESTAMP;
            
            
            RETURN QUERY
                SELECT puserID,
                 'The token is deleted.',
                 NULL,
                 NULL,
                 NULL,
                 NULL::timestamp;
        END IF;
    ELSE
    RETURN QUERY 
        SELECT puserID,
            'Invalid request type. Available request types are: (create), (renew), (delete).',
            NULL, NULL, NULL, NULL;
    END CASE;
END;
$$
LANGUAGE PLPGSQL;
```

##### Funkcja sprawdzająca, czy zadane argumentami ID oraz hasło użytkownika zgadzają się z danymi przechowywanymi w bazie

```sql
CREATE OR REPLACE FUNCTION validate_sign_in (puserID text, ppassword text)
    RETURNS boolean
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM Users AS U
        WHERE U.ID = puserID::uuid
            AND U.password = crypt(ppassword, U.password)
    ) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$
LANGUAGE PLPGSQL;
```

## Wyzwalacze

*Komentarze dotyczące działania funkcji wywoływanych przez wyzwalacze są dostępne [w kolejnej sekcji](#procedury-wyzwalaczy), wraz z ich implementacjami.*

```sql
CREATE TRIGGER hash_password
    BEFORE INSERT ON Users
    FOR EACH ROW
    EXECUTE FUNCTION hash_password_trigger ();
```

```sql
CREATE TRIGGER register_user
    AFTER INSERT ON Users
    FOR EACH ROW
    EXECUTE FUNCTION register_user_trigger ();
```

```sql
CREATE TRIGGER check_couple
    BEFORE INSERT ON Couples
    FOR EACH ROW
    -- Check if couple already exists (prevent (1,2) (2,1))
    -- and if both people are owned by the same user
    EXECUTE FUNCTION check_couple_trigger ();
```

```sql
CREATE TRIGGER before_add_couple
    BEFORE INSERT ON Couples
    FOR EACH ROW
    EXECUTE FUNCTION before_add_couple_trigger ();
```

```sql
CREATE TRIGGER after_add_couple
    AFTER INSERT ON Couples
    FOR EACH ROW
    EXECUTE FUNCTION after_add_couple_trigger ();
```

```sql
CREATE TRIGGER add_tree
    BEFORE INSERT ON Trees
    FOR EACH ROW
    EXECUTE FUNCTION check_tree_trigger ();
```

```sql
CREATE TRIGGER save_payment
    AFTER INSERT ON Payments
    FOR EACH ROW
    EXECUTE FUNCTION save_payment_trigger ();
```

```sql
CREATE TRIGGER change_preferences
    BEFORE INSERT OR UPDATE ON Preferences
    FOR EACH ROW
    EXECUTE FUNCTION change_preferences_trigger ();
```

## Procedury wyzwalaczy

##### Sprawdzanie duplikatowych par, które nie są kluczami głównymi, ani nie są sprawdzane przez CHECK 

```sql
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
                WHERE ID = NEW.secondPersonID
            ) THEN
                RAISE 'Cannot couple people from different owners: "%" and "%"', (
                    SELECT ownerID FROM People
                    WHERE ID = NEW.firstPersonID), (
                    SELECT ownerID FROM People
                    WHERE ID = NEW.secondPersonID);
    END IF;
    RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;
```

##### Gdy dodajemy związek do tabeli, a nie ma on jeszcze przydzielonego drzewa, to dopisujemy ID drzewa do wiersza (korzystając z ID drzew, do których należą członkowie związku)

```sql
CREATE OR REPLACE FUNCTION before_add_couple_trigger ()
    RETURNS TRIGGER
    AS $$
DECLARE firstPersonTreeID int;
DECLARE secondPersonTreeID int;
BEGIN    
    IF (NEW.treeID IS NULL) THEN
        firstPersonTreeID := (SELECT treeID FROM People WHERE ID = NEW.firstPersonID);
        secondPersonTreeID := (SELECT treeID FROM People WHERE ID = NEW.secondPersonID);

        IF (firstPersonTreeID != secondPersonTreeID) THEN
            RAISE 'Cannot create a couple from persons from different trees';
        END IF;

        INSERT INTO Couples (ID, firstPersonID, secondPersonID, treeID)
            VALUES (NEW.ID, NEW.firstPersonID, NEW.secondPersonID, firstPersonTreeID);
        
        RETURN null;
    END IF;

    RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;
```

##### Po dodaniu pary posiadającej (zagwarantowane wyżej) ID drzewa, jeśli jest to pierwsza para w drzewie - dodaj ją jako korzeń

```sql
CREATE OR REPLACE FUNCTION after_add_couple_trigger ()
    RETURNS TRIGGER
    AS $$
BEGIN
    UPDATE Trees AS T
        SET rootCoupleID = NEW.ID
        WHERE T.ID = NEW.treeID
              AND rootCoupleID IS NULL;
        
    RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;
```

##### Gdy dodajemy użytkownika, tworzymy rekord jego dotyczący w tabeli zawierającej historię rejestracji

```sql
CREATE OR REPLACE FUNCTION register_user_trigger ()
    RETURNS TRIGGER
    AS $$
BEGIN
    INSERT INTO Registrations (userID, registrationDate)
        VALUES (NEW.ID, LOCALTIMESTAMP);
    RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;
```

##### Sprawdzamy, czy użytkownik ma możliwość stworzenia kolejnego drzewa, zależnie od rodzaju subskrypcji

```sql
CREATE OR REPLACE FUNCTION add_tree_trigger ()
  RETURNS TRIGGER
  AS $$
DECLARE subscriptionType text;
DECLARE currentTreeCount int;
BEGIN
   subscriptionType := (SELECT CS.subscriptionType
                        FROM current_subscribers AS CS
                        WHERE CS.userID = NEW.ownerID);
                        
   currentTreeCount := (SELECT COUNT(*)
                        FROM Trees AS T
                        WHERE T.ownerID = NEW.ownerID);

   CASE subscriptionType
     WHEN 'Business' THEN
         IF currentTreeCount >= 60 THEN
             RAISE 'You can have at most 60 trees at the same time';
         END IF;
     WHEN 'Premium' THEN
         IF currentTreeCount >= 40 THEN
             RAISE 'You can have at most 40 trees at the same time';
         END IF;
     WHEN 'Basic' THEN
         IF currentTreeCount >= 30 THEN
             RAISE 'You can have at most 30 trees at the same time';
         END IF;
     ELSE
         IF currentTreeCount >= 15 THEN
             RAISE 'You can have at most 15 trees at the same time';
         END IF;
   END CASE;

  RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;
```

##### Gdy zapisywana jest płatność automatycznie przedłużamy, bądź przydzielamy subskrypcję użytkownikowi

```sql
CREATE OR REPLACE FUNCTION save_payment_trigger ()
    RETURNS TRIGGER
    AS $$
BEGIN
    IF NEW.errorMessage IS NULL THEN
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
```

##### Sprawdzanie warunków koniecznych do korzystania z określonych ustawień

```sql
CREATE OR REPLACE FUNCTION change_preferences_trigger ()
    RETURNS TRIGGER
    AS $$
BEGIN
    IF NEW.showDates = true THEN
        IF NOT EXISTS (SELECT 1 FROM current_subscribers AS CS
                                     WHERE CS.userID = NEW.userID
                                          AND CS.subscriptionType IN ('Basic', 'Premium', 'Business')) THEN
            RAISE 'Could not save preferences. You need at least Basic subscription';
        END IF;
    END IF;
    
    IF NEW.exportInDarkTheme = true THEN
        IF NOT EXISTS (SELECT 1 FROM current_subscribers AS CS
                                     WHERE CS.userID = NEW.userID
                                          AND CS.subscriptionType IN ('Premium', 'Business')) THEN
            RAISE 'Could not save preferences. You need at least Premium subscription';
        END IF;
    END IF;
    
    IF NEW.useBoldFonts = true THEN
        IF NOT EXISTS (SELECT 1 FROM current_subscribers AS CS
                                     WHERE CS.userID = NEW.userID
                                          AND CS.subscriptionType = 'Business') THEN
            RAISE 'Could not save preferences. You need at least Business subscription';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$
LANGUAGE PLPGSQL;
```

## Skrypt tworzący bazę danych

```sql
CREATE DATABASE "ProjektBD";

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

DROP TABLE IF EXISTS Payments CASCADE;

DROP TABLE IF EXISTS Tokens;


-- Tworzenie tabel

CREATE TABLE IF NOT EXISTS Users (
    ID uuid PRIMARY KEY DEFAULT uuid_generate_v4 (),
    username text UNIQUE NOT NULL,
    email text UNIQUE NOT NULL,
    password text NOT NULL,
    CHECK (COALESCE(TRIM(username), '') != ''),
    CHECK (COALESCE(TRIM(email), '') != '')
);

CREATE TABLE IF NOT EXISTS People (
    ID serial PRIMARY KEY,
    ownerID uuid NOT NULL REFERENCES Users (ID) ON DELETE CASCADE,
    treeID int NOT NULL,
    firstName text NOT NULL,
    lastName text NOT NULL,
    additionalName text,
    birthName text,
    dateOfBirth date,
    dateOfDeath date,
    parentCoupleID int
);

CREATE TABLE IF NOT EXISTS Couples (
    ID serial UNIQUE NOT NULL,
    firstPersonID int NOT NULL REFERENCES People (ID) ON DELETE CASCADE,
    secondPersonID int NOT NULL REFERENCES People (ID) ON DELETE CASCADE,
    treeID int NOT NULL,
    PRIMARY KEY (firstPersonID, secondPersonID),
    CHECK (firstPersonID != secondPersonID)
);

CREATE TABLE IF NOT EXISTS Trees (
    ID serial PRIMARY KEY,
    name text NOT NULL,
    ownerID uuid NOT NULL REFERENCES Users (ID) ON DELETE CASCADE,
    rootCoupleID int REFERENCES Couples (ID) ON DELETE CASCADE,
    UNIQUE (ID, ownerID)
);

ALTER TABLE People
    ADD CONSTRAINT fk_parentCouple FOREIGN KEY (parentCoupleID) REFERENCES Couples (ID) ON DELETE SET NULL,
    ADD CONSTRAINT fk_trees FOREIGN KEY (treeID) REFERENCES Trees (ID) ON DELETE CASCADE;
    
ALTER TABLE Couples
    ADD CONSTRAINT fk_trees FOREIGN KEY (treeID) REFERENCES Trees (ID) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS Registrations (
    userID uuid PRIMARY KEY, -- NO REFERENCES Users (ID), since we don't want to lose registration data on user deletion
    registrationDate timestamp NOT NULL
);

CREATE INDEX IF NOT EXISTS user_idx ON Registrations (userID);

CREATE TABLE IF NOT EXISTS Preferences (
    userID uuid PRIMARY KEY REFERENCES Users (ID) ON DELETE CASCADE,
    newsletter boolean,
    showDates boolean, -- requires basic
    exportInDarkTheme boolean, -- requires premium
    useBoldFonts boolean -- requires business
);

CREATE TABLE IF NOT EXISTS "Subscription Types" (
    type text PRIMARY KEY,
    price money NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS Subscribers (
    userID uuid NOT NULL REFERENCES Users (ID) ON DELETE CASCADE,
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
    userID uuid NOT NULL REFERENCES Users (ID) ON DELETE CASCADE,
    method text NOT NULL REFERENCES "Payment Methods" (method),
    subscriptionType text REFERENCES "Subscription Types" (type) NOT NULL,
    errorMessage text,
    total money NOT NULL,
    timestamp timestamp NOT NULL,
    PRIMARY KEY (userID, timestamp)
);

CREATE TABLE IF NOT EXISTS Tokens (
    userID uuid NOT NULL REFERENCES Users (ID) ON DELETE CASCADE,
    applicationName text NOT NULL,
    token text NOT NULL,
    renewToken text NOT NULL,
    deleteToken text NOT NULL,
    expires timestamp NOT NULL,
    PRIMARY KEY (userID, token)
);

-- Własne typy

DO
LANGUAGE PLPGSQL
$$
BEGIN
    DROP TYPE IF EXISTS TokenRequestType CASCADE;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type
        WHERE typname = 'tokenrequesttype') THEN
    CREATE TYPE TokenRequestType AS ENUM ('create', 'renew', 'delete');
    END IF;
END$$;

```

## Przykładowe zapytania

```sql
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
--  VALUES (1, 9);

-- BŁĄD
--INSERT INTO Couples (firstPersonID, secondPersonID)
--  VALUES (1, 2);

-- BŁĄD
--INSERT INTO Couples (firstPersonID, secondPersonID)
--  VALUES (2, 1);


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
```
