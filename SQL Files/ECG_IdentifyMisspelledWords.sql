/*
ECG_IdentifyMisspelledWords

Identified words in the EKG narratives that are misspelled by matching to the ecg_spelling table
and the misspelling table This will identify new misspelled words that should be added to the tab-delimited file ECG_Misspellings.txt

Words that are spelled correctly shoulde be added to the tab-delimited file ECG_Spelling.txt
Then reimport the configuration files using the stored procedure [dbo].[ECG_CreateTablesForNLProcessing]

Author: Richard H. Epstein, MD
Copyright (C) 2020


Date		Ver		By		Comment
09/11/20	1.00	RHE		Initial Coding
01/13/21	2.00	RHE		Code for distribution in Google drive



*/

CREATE PROC [dbo].[ECG_IdentifyMisspelledWords]
AS

  SET NOCOUNT ON

  -- **************************
  -- 05/14/19 RHE break out the narratives to all words so can check spelling errors 
  -- do not consider narrative with Test Reason as those are not used in the algorithm and the source of most spelling errors
  -- I used NLTK toolkit to generate a dictionary of words in dbo.Spelling
  -- these included several online ECG tutorial and the websters unabrideged dictionary
  -- **************************

  IF OBJECT_ID('tempdb.dbo.#Sentences') IS NOT NULL
    DROP TABLE #Sentences
  IF OBJECT_ID('tempdb.dbo.#SingleWords') IS NOT NULL
    DROP TABLE #SingleWords
  IF OBJECT_ID('tempdb.dbo.#UniqueWords') IS NOT NULL
    DROP TABLE #UniqueWords
  IF OBJECT_ID('tempdb.dbo.#EKG') IS NOT NULL
    DROP TABLE #EKG
  IF OBJECT_ID('tempdb.dbo.#WordsToCheckSpelling') IS NOT NULL
    DROP TABLE #WordsToCheckSpelling

  CREATE TABLE #Sentences (
    idx int IDENTITY (1, 1),
    narrative varchar(1024)
  )
  CREATE TABLE #SingleWords (
    idx int IDENTITY (1, 1),
    word varchar(255)
  )
  CREATE TABLE #UniqueWords (
    word varchar(255),
    n int
  )
  CREATE TABLE #EKG (
    idx int IDENTITY (1, 1),
    Narrative varchar(1024)
  )
  CREATE TABLE #WordsToCheckSpelling (
    word varchar(100)
  )


  TRUNCATE TABLE #EKG

  INSERT INTO #EKG
    SELECT DISTINCT
      narrativeraw
    FROM dbo.ECG_Narratives
    WHERE ignore = 0

  TRUNCATE TABLE #Sentences
  INSERT INTO #sentences
    SELECT
      LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(narrative, '        ', ' '), '       ', ' '), '      ', ' '), '    ', ' '), '   ', ' '), '  ', ' '), '  ', ' '), '  ', ' '), '"', ' ')))
    FROM #EKG

  UPDATE #Sentences
  SET narrative =
  REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE
  (narrative, '.', ' '), ',', ' '), ';', ' '), '/', ' '), '  ', ' '), '(', ' '), ')', ' '), '[', ' '), ']', ' '), '\', ''), '"', ' '), '*', ' '), '+', ' '), '>', ' '), '<', ' '), '=', ' '), '?', ' '), '~', ' '), '!', ' '), '''', ' ')


  -- *******************************
  DECLARE @nWordsLeft int = (SELECT
    COUNT(idx)
  FROM #Sentences
  WHERE CHARINDEX(' ', narrative) > 0)
  TRUNCATE TABLE #SingleWords


  WHILE @nWordsLeft > 0
  BEGIN
    INSERT INTO #SingleWords
      SELECT
        CASE
          WHEN CHARINDEX(' ', Narrative) = 0 THEN Narrative
          ELSE SUBSTRING(narrative, 1, CHARINDEX(' ', Narrative) - 1)
        END
      FROM #Sentences
      WHERE LEN(narrative) > 0

    UPDATE #Sentences
    SET narrative = SUBSTRING(narrative, CHARINDEX(' ', Narrative) + 1, 255)

    SELECT
      @nWordsLeft = (SELECT
        COUNT(idx)
      FROM #Sentences
      WHERE CHARINDEX(' ', narrative) > 0)
    DELETE FROM #Sentences
    WHERE LEN(narrative) = 0
  END


  -- when get to the end there will be single words left in the #Sentences tables wwith no spaces. add them
  INSERT INTO #SingleWords
    SELECT
      narrative
    FROM #Sentences

  -- get rid of . and , and other punctution marks
  UPDATE #SingleWords
  SET word = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(word, '.', ' '), ',', ' '), ';', ' '), '/', ' '), '  ', ' '), '(', ' '), ')', ' '), '[', ' '), ']', ' '), '\', '')


  TRUNCATE TABLE #UniqueWords
  INSERT INTO #UniqueWords
    SELECT
      LTRIM(RTRIM(word)),
      COUNT(word) AS n
    FROM #SingleWords
    GROUP BY LTRIM(RTRIM(word))
    ORDER BY n DESC



  TRUNCATE TABLE #WordsToCheckSpelling
  INSERT INTO #WordsToCheckSpelling
    SELECT DISTINCT
      word
    FROM #UniqueWords
    WHERE LEN(word) > 4
    AND word NOT LIKE '%:%'
    AND word NOT LIKE '%[0-9][0-9]-%'
    AND word NOT LIKE '%/%/%'
    AND word NOT LIKE '%-%-%'
    AND word NOT LIKE '%[0-9][0-9][0-9][0-9]%'
    AND word NOT LIKE '%/%'
    ORDER BY word

  -- replace words starting with a -
  UPDATE #WordsToCheckSpelling
  SET word = REPLACE(word, '-', '')
  WHERE SUBSTRING(word, 1, 1) = '-'

  -- remove words in the spelling table. these are ok
  DELETE FROM #WordsToCheckSpelling
    FROM #WordsToCheckSpelling a
    INNER JOIN dbo.ecg_spelling b
      ON a.word = b.word



  -- remove words already in the misspelling table. 
  DELETE FROM #WordsToCheckSpelling
    FROM #WordsToCheckSpelling a
    INNER JOIN dbo.ecg_misspellings b
      ON a.word = b.bad

  -- remove words that are dates or start with numbers
  DELETE FROM #WordsToCheckSpelling
    FROM #WordsToCheckSpelling
  WHERE word LIKE '%[0-9][ /][0-9]%[ /][0-9][0-9]%'
    OR word LIKE '[0-9]%'

  -- words to check and supply corrected spelling
  SELECT
    word
  FROM #WordsToCheckSpelling




  IF OBJECT_ID('tempdb.dbo.#EKG') IS NOT NULL
    DROP TABLE #EKG
  IF OBJECT_ID('tempdb.dbo.#Sentences') IS NOT NULL
    DROP TABLE #Sentences
  IF OBJECT_ID('tempdb.dbo.#SingleWords') IS NOT NULL
    DROP TABLE #SingleWords
  IF OBJECT_ID('tempdb.dbo.#UniqueWords') IS NOT NULL
    DROP TABLE #UniqueWords
  IF OBJECT_ID('tempdb.dbo.#WordsToCheckSpelling') IS NOT NULL
    DROP TABLE #WordsToCheckSpelling







