/*
ECG_PreProcessNarratives

Description:
	Correct spelling mistakes in the dbo.ECG_Narratives table NarrativeRaw field and copy to the Narrative field

 
Author: Richard H. Epstein, MD
Copyright (C) 2020


IMPORTANT NOTES: 

Syntax:
	EXEC dbo.ECG_PreProcessNarratives	
	
	
Performance:
	240 sec for 56177 ECG	4.27 msec/EKG   
	



Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding
01/21/20	1.01	RHE		Performance improvements


*/

--/*
CREATE PROC [dbo].[ECG_PreProcessNarratives]
AS
  --*/

  SET NOCOUNT ON

  -- *************************************************************************************
  -- *** determine what words are misspelled in the EKG narratives and then correct them
  -- *************************************************************************************

  IF OBJECT_ID('tempdb.dbo.#Corrections') IS NOT NULL
    DROP TABLE #Corrections
  IF OBJECT_ID('tempdb.dbo.#Misspellings') IS NOT NULL
    DROP TABLE #Misspellings


  CREATE TABLE #Misspellings (
    IDX int IDENTITY,
    word varchar(255),
    correction varchar(255)
  )

  CREATE TABLE #Corrections (
    IDXcorrection int IDENTITY (1, 1),
    idx int,
    narrative varchar(255),
    narrative_corrected varchar(1024),
    bad varchar(255),
    good varchar(255),
    Processed tinyint
  )

  -- select top 100 * from dbo.ECG_Narratives

  -- ****************************************
  -- eliminate lines from the dbo.ECG_Narratives table that are blank or empty
  -- ****************************************
  DELETE FROM dbo.ECG_Narratives
  WHERE RTRIM(ISNULL(NarrativeRaw, '')) = ''

  -- ****************************************
  -- * copy narrative raw to narrative
  -- * Get rid of superfluous punctuation, and double spaces 
  -- * add a space at the start and end of each line to allow the matching to not have to deal with the word boundary issue for 
  -- * misspelled words at the start and end of the line
  -- * Punctuation replaced with single space: ,.;!?" and tab
  -- * 1/21/21 RHE
  -- ****************************************

  UPDATE dbo.ECG_Narratives
  SET Narrative =
      REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(NarrativeRaw, ',', ' '), ';', ' '), '!', ' '), '?', ' '), CHAR(9), ' '), '"', ' '), '.', ' '),
      Ignore = 0


  -- get rid of empty lines after removing punctuation
  DELETE FROM dbo.ECG_Narratives
  WHERE RTRIM(ISNULL(Narrative, '')) = ''

  -- insert a space at the start and end of each narrative to avoid word boundry issues at the start and end of each line
  UPDATE dbo.ECG_Narratives
  SET Narrative = ' ' + Narrative + ' '




  -- ******************************************************
  -- * Find the words in the misspelling table that are present in the narratives
  -- ******************************************************
  TRUNCATE TABLE #Misspellings

  INSERT INTO #Misspellings
    SELECT DISTINCT
      bad,
      good
    FROM dbo.ECG_Misspellings a,
         (SELECT DISTINCT
           Narrative
         FROM dbo.ECG_Narratives) x
    WHERE CHARINDEX(bad, Narrative) > 0

  TRUNCATE TABLE #Corrections

  DECLARE @sql2 nvarchar(1024)
  DECLARE @nMisspelled int = (SELECT
    MAX(idx)
  FROM dbo.ECG_Misspellings)

  DECLARE @nn int = 1
  DECLARE @good varchar(100)
  DECLARE @bad varchar(100)


  -- regex expressions below account for word boundry issues
  WHILE @nn <= @nMisspelled
  BEGIN
    SET @good = (SELECT
      REPLACE(correction, '''', '''''')
    FROM #Misspellings
    WHERE idx = @nn)
    SET @bad = (SELECT
      REPLACE(word, '''', '''''')
    FROM #Misspellings
    WHERE idx = @nn)

    SELECT
      @SQL2 =
      N'
	insert into #Corrections (idx, narrative,  narrative_corrected, bad, good) 
	select distinct 
	idx, 
	Narrative, 
	replace(Narrative, ''' + @bad + ''' , ''' + @good + ''' ),'''
      + @bad + ''',''' + @good + ''' 
	from dbo.ECG_Narratives
	where
	( 
		Narrative like ''% ' + @bad + ' %''
	) 
	'

    EXEC sp_executesql @SQL2

    -- make corrections each pass beacuse there can be multiple errors in the same line
    UPDATE dbo.ECG_Narratives
    SET NARRATIVE = B.narrative_corrected
    FROM dbo.ECG_Narratives a
    INNER JOIN #Corrections b
      ON a.idx = b.idx
    WHERE b.processed IS NULL

    UPDATE #Corrections
    SET processed = 1
    WHERE processed IS NULL

    SET @nn = @nn + 1
  END



  -- *************************************
  -- * Get rid of leading and trailing spaces that previously were added
  -- **************************************
  UPDATE dbo.ECG_Narratives
  SET Narrative = LTRIM(RTRIM(Narrative))



  -- *********************************
  -- * get rid oF double spaces
  -- *********************************
  DECLARE @nRows integer = 1

  WHILE @nRows > 0
  BEGIN
    UPDATE dbo.ECG_Narratives
    SET Narrative = REPLACE(REPLACE(narrative, '   ', ' '), '  ', ' ')
    WHERE CHARINDEX('  ', narrative) > 0

    SET @nRows = @@ROWCOUNT
  END


  -- *******************************************************************************
  -- mark rows to ignore with a 0 that are not diagnoses and should not be processed
  -- mark rows that will be processed as quantitative data with a 2
  -- ********************************************************************************
  -- These are rows with quantitative information
  UPDATE dbo.ECG_Narratives
  SET ignore = 2
  FROM dbo.ECG_Narratives a, dbo.ECG_QuantitativeMatch b
  WHERE CHARINDEX(b.MatchString, a.narrative) > 0
  AND a.ignore = 0

  -- these are rows with non-diagnostic and non-quantitative data
  UPDATE dbo.ECG_Narratives
  SET ignore = 1		-- 
  FROM dbo.ECG_Narratives a, dbo.ECG_DiagnosisExclusions b
  -- 02/17/21 RHE force exclusion to start the line
  WHERE CHARINDEX(b.phrase, a.narrative) = 1
  AND a.ignore = 0


  UPDATE dbo.ECG_Narratives
  SET Ignore = 1
  FROM dbo.ECG_Narratives a, dbo.ECG_MatchTypeExclusion b
  WHERE CHARINDEX(b.ExcludeMatchString, a.narrative) > 0
  AND a.ignore = 0
  AND matchType = 2


  -- get rid of signature names that are not preced by reviewed by, etc.
  UPDATE dbo.ECG_Narratives
  SET Ignore = 1
  WHERE narrative LIKE '%/%/%:%[AP]M%'   -- these have dates and timesa datetime
  AND IGNORE = 0


  -- 02/20/21 If you want to include all rows for processing, not excluding as above, uncomment the next line
  -- UPDATE dbo.ECG_Narratives SET Ignore = 0

  -- If the word versus, vs or vs. is present, then replace it with possible and add possible at the start of the narrative
  UPDATE dbo.ECG_Narratives
  SET narrative = 'Possible ' + narrative
  WHERE (narrative LIKE '%versus%'
  OR narrative LIKE '% vs %'
  OR narrative LIKE '% vs. %')
  AND narrative NOT LIKE 'Cannot%'
  AND narrative NOT LIKE 'Possib%'
  AND narrative NOT LIKE 'Probab%'
  AND narrative NOT LIKE 'Test %'
  AND ignore = 0


  UPDATE dbo.ECG_Narratives
  SET narrative = REPLACE(Narrative, ' versus', ' versus Possible ')
  UPDATE dbo.ECG_Narratives
  SET narrative = REPLACE(Narrative, ' vs ', ' versus Possible ')
  UPDATE dbo.ECG_Narratives
  SET narrative = REPLACE(Narrative, ' vs. ', ' versus Possible ')


  IF OBJECT_ID('tempdb.dbo.#Corrections') IS NOT NULL
    DROP TABLE #Corrections
  IF OBJECT_ID('tempdb.dbo.#Misspellings') IS NOT NULL
    DROP TABLE #Misspellings



