/*
ECG_ProcessNarratives

Process the ECG narratives in the table dbo.ECG_Narratives and saves results into table dbo.ECG_DiagnosticInfo

Author: Richard H. Epstein, MD
Copyright (C) 2020

Syntax
	EXEC dbo.ECG_ProcessNarratives		-- process the narratives and produce the dbo.ECG_ResultsQuantitative and dbo.ECG_ResultsDiagnosis tables
	EXEC dbo.ECG_ProcessNarratives 0	-- same as with no parameter suplied
	EXEC dbo.ECG_ProcessNarratives 1	-- process the narratives as above and also generate the additional tables to evaluate performance of the algorithm
						
						
Examine the input file
	Select * from dbo.ECG_Narratives										

Examine the quantitative and diagnosis output tables
	Select top 100 * from dbo.ECG_ResultsQuantitative			-- quantitative values from the ECG narratives
	Select top 100 * from dbo.ECG_ResultsDiagnostic				-- diagnostic information from the ECG narratives

Examine the performance output tables
	Select  * from [dbo].[ECG_PerformanceAllNarratives]							-- 
	Select top 100 * from [dbo].[ECG_PerformanceDiscreteNarratives]				--	
	Select top 100 * from [dbo].[ECG_PerformanceNarrativesWithoutDiagnosis]		-- narrative lines that did not match to a diagnosis


Instructions
1.	Execute the proc dbo.ECG_CreateTablesForNLProcessing to create the tables needed for processing
2.  If using Epic
	Execute the proc ECG_DetermineEpicECGIdentifiers to determine the relevant values of ORDER_TYPE_C and PROC_iD
	Modify dbo.ECG_LoadNarratives to use the local Epic values
3.	If using Epic	
	Execute dbo.ECG_LoadNarratives to insert the ECG narratives into the table dbo.ECG_Narratives
	If not using Epic
	Load the ECG narratives into the table dbo.ECG_Narratives using your own procedure
3.	Exec dbo.ECG_IdentifiedMisspelledWords and add misspelled word mappings into the table dbo.ECG_MisspelledWords
4.  Change the value of @MaxLineLength as necessary in the stored procedure and then execute the code to alter the procedure. Default is 130 for the MUSE system
5.  Execute the current procedure dbo.ECG_ProcessNarratives to extract the diagnostic and quantitative information from the ECG narratives


select top 100 * from dbo.ECG_Narratives order by ORDER_PROC_ID, linenumber
select top 100 * from dbo.ECG_ResultsQuantitative order by ORDER_PROC_ID
select top 100 * from dbo.ECG_ResultsDiagnostic order by ORDER_PROC_ID, Diagnosis

Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding
01/13/20	2.00	RHE		Modified code for distribution in the Google drive folder
01/20/21	2.01	RHE		Moved code to preprocess the narratitve into dbo.ECG_Preprocessnarratives. Removed coresponding code here
							This will allow more rapid modification of the configuraiton tables for diagnosis processing	
02/24/21	2.02	RHE		Modified code for processing complex lines excluding historical diagnoses to include ' however '
*/

--/*
CREATE PROC [dbo].[ECG_ProcessNarratives] @EvaluatePerformance tinyint = 0
AS
  --*/

  SET NOCOUNT ON

  /*
  DECLARE @EvaluatePerformance tinyint = 1 -- 1= generate the output for analysis of the processing;  0=skip the analysis (for production use)
  --*/


  /* --for performance evaluation
  declare @Time1 datetime, @Time2 datetime
  set @Time1 = getdate()
  */


  -- **************************************************
  -- Set the max number of characters to determine if the line is continued
  -- **************************************************
  DECLARE @MaxLineLength smallint = 130

  IF OBJECT_ID('tempdb.dbo.#EKGSummary') IS NOT NULL
    DROP TABLE #EKGSummary
  IF OBJECT_ID('tempdb.dbo.#DiagnosisExclusions') IS NOT NULL
    DROP TABLE #DiagnosisExclusions
  IF OBJECT_ID('tempdb.dbo.#HedgePhrases') IS NOT NULL
    DROP TABLE #HedgePhrases
  IF OBJECT_ID('tempdb.dbo.#QuantitativeMatch') IS NOT NULL
    DROP TABLE #QuantitativeMatch
  IF OBJECT_ID('tempdb.dbo.#MatchTypeExclusion') IS NOT NULL
    DROP TABLE #MatchTypeExclusion
  IF OBJECT_ID('tempdb.dbo.#EKG') IS NOT NULL
    DROP TABLE #EKG
  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosesNoLongerPresent') IS NOT NULL
    DROP TABLE #ECG_DiagnosesNoLongerPresent
  IF OBJECT_ID('tempdb.dbo.#DiagnosisEvaluation') IS NOT NULL
    DROP TABLE #DiagnosisEvaluation
  IF OBJECT_ID('tempdb.dbo.#EKG_Quantitative') IS NOT NULL
    DROP TABLE #EKG_Quantitative
  IF OBJECT_ID('tempdb.dbo.#EKGSummary') IS NOT NULL
    DROP TABLE #EKGSummary
  IF OBJECT_ID('tempdb.dbo.#SQL') IS NOT NULL
    DROP TABLE #SQL
  IF OBJECT_ID('tempdb.dbo.#DiagnosisEvaluationHedged') IS NOT NULL
    DROP TABLE #DiagnosisEvaluationHedged
  IF OBJECT_ID('tempdb.dbo.#Performance') IS NOT NULL
    DROP TABLE #Performance
  IF OBJECT_ID('tempdb.dbo.#UniqueNarratives') IS NOT NULL
    DROP TABLE #UniqueNarratives

  -- hedge phrases
  CREATE TABLE #DiagnosisEvaluationHedged (
    IDX int,
    PAT_ID varchar(18),
    ORDER_PROC_ID decimal(18, 0),
    ECGDate datetime,
    NarrativeRaw varchar(1024),
    Narrative varchar(1024),
    Code char(3),
    Diagnosis varchar(100),
    DiagnosisUncertain tinyint,
    MatchLocation int,
    Ignore tinyint,
    HedgeCode char(3),
    HedgePhrase varchar(30),
    HedgeLocation int
  )


  -- match diagnoses
  CREATE TABLE #DiagnosisEvaluation (
    IDX int IDENTITY (1, 1),
    PAT_ID varchar(18),
    ORDER_PROC_ID decimal(18, 0),
    ECGDate datetime,
    NarrativeRaw varchar(1024), -- -2/18/21 RHE add here so can have the original line
    Narrative varchar(1024),
    Code char(3),
    Diagnosis varchar(100),
    DiagnosisUncertain tinyint,	-- if diagnosis is preceded by a hedge word such as possible, cannot rule out, cannot exclude, etc
    MatchLocation int,
    Ignore tinyint
  )

  -- summary table for quantitative assessment of EKG
  CREATE TABLE #EKGSummary (
    pat_id varchar(18),
    ORDER_PROC_ID numeric(18),
    EKGDate datetime,
    Description varchar(30),
    Indication varchar(100),
    QT smallint,
    P_Axis smallint,
    R_Axis smallint,
    T_Axis smallint,
    QRS smallint,
    PR smallint,
    QTc smallint,
    V_Rate smallint,
    A_Rate smallint,
    Interpreter varchar(255),
    InterpretationTime datetime
  )

  -- phrases to exclude from processing diagnoses, as these are quantitative or non-diagnostic (administrative) info
  CREATE TABLE #DiagnosisExclusions (
    Phrase varchar(100)
  )

  CREATE TABLE #HedgePhrases (
    code char(3),
    phrase varchar(30)
  )

  -- specifications for the quantitative information at the top of the ECG narrative
  CREATE TABLE #QuantitativeMatch (
    MatchType smallint,
    MatchString varchar(100), --	string to search for
    VariableName varchar(60), --	name of the value to report
    Offset smallint,		  --	offset # of chars from the start of the match string to the first character/digit of the value
    StringLength smallint,	  --    number of characters in the value; 999 means rest of the line
    Allow0 tinyint,			  --	if 0 means that a value of 0 is not allowed and will be replaced with a null if empty; 1 means the value can be empty
    StringValue tinyint		  --    1 means that the value is a string; 0 an integer
  )

  -- insert exclusions here that apply to all matches of same type
  -- 1 = diagnostic criterion
  CREATE TABLE #MatchTypeExclusion (
    MatchType smallint,
    ExcludeMatchString varchar(100)
  )

  -- table for processing the ECGs
  CREATE TABLE #EKG (
    idx int IDENTITY (1, 1),
    PAT_ID varchar(18),
    ORDER_PROC_ID varchar(18),
    contact_date datetime,
    Description varchar(255),
    line int,
    Narrative varchar(1024),
    NarrativeRaw varchar(1024),
    Ignore tinyint
  )

  CREATE TABLE #ECG_DiagnosesNoLongerPresent (
    IDX int IDENTITY (1, 1),
    ReplacementType varchar(6),
    Phrase varchar(100)
  )

  TRUNCATE TABLE #DiagnosisExclusions
  INSERT INTO #DiagnosisExclusions
    SELECT
      Phrase
    FROM dbo.ECG_DiagnosisExclusions
    ORDER BY IDX
  -- select * from #DiagnosisExclusions

  TRUNCATE TABLE #HedgePhrases
  INSERT INTO #HedgePhrases
    SELECT
      CODE,
      Phrase
    FROM dbo.ECG_HedgePhrases
    ORDER BY IDX
  -- select * from #HedgePhrases

  TRUNCATE TABLE #QuantitativeMatch
  INSERT INTO #QuantitativeMatch
    SELECT
      MatchType,
      MatchString,
      VariableName,
      Offset,
      StringLength,
      Allow0,
      StringValue
    FROM dbo.ECG_QuantitativeMatch
    ORDER BY IDX
  -- select * from #QuantitativeMatch

  -- insert exclusions here that apply to all matches of same type
  -- match types
  -- 1 = diagnostic criterion

  -- drop table #MatchTypeExclusion
  TRUNCATE TABLE #MatchTypeExclusion
  INSERT INTO #MatchTypeExclusion
    SELECT
      MatchType,
      ExcludeMatchString
    FROM dbo.ECG_MatchTypeExclusion
    ORDER BY IDX
  --select * from #MatchTypeExclusion

  -- *********************************************
  -- * Load  ECG narratives from the table dbo.ECG_Narratives
  -- * This table has already been processed to fix spelling errors
  -- * so the field narrative has the corrected strings
  -- *********************************************
  TRUNCATE TABLE #EKG
  INSERT INTO #EKG
    SELECT
      PATIENT_ID,
      ORDER_PROC_ID,
      ECGDate,
      ECGDescription,
      LineNumber,
      Narrative AS Narrative,
      NarrativeRaw AS NarrativeRaw,
      ignore
    FROM dbo.ECG_Narratives
    WHERE narrative IS NOT NULL
    ORDER BY PATIENT_ID,
    ORDER_PROC_ID,
    LineNumber

  TRUNCATE TABLE #ECG_DiagnosesNoLongerPresent
  INSERT INTO #ECG_DiagnosesNoLongerPresent
    SELECT
      ReplacementType,
      Phrase
    FROM dbo.ECG_DiagnosesNoLongerPresent
    ORDER BY IDX
  -- select * from #ECG_DiagnosesNoLongerPresent


  -- narratives are continued on the next line if the len>150 so combine if len=150 and first char of next line is not a capital
  -- if need to explore the length, uncomment the next line and change the value of @MaxLineLength
  -- declare @MaxLineLength smallint = 130

  UPDATE a
  SET a.narrative = RTRIM(a.narrative) + ' ' + LTRIM(b.narrative)
  FROM #EKG a
  INNER JOIN #EKG b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
    AND a.line = b.line - 1
  WHERE LEN(a.narrative) >= @MaxLineLength
  AND (ASCII(SUBSTRING(LTRIM(b.narrative), 1, 1)) NOT BETWEEN 65 AND 90)  -- skip upper case first letters

  -- delete the narrative where the line is a continuation line, as from the previous block
  UPDATE b
  SET b.narrative = ''
  FROM #EKG a
  INNER JOIN #EKG b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
    AND a.line = b.line - 1
  WHERE LEN(a.narrative) >= @MaxLineLength
  AND (ASCII(SUBSTRING(LTRIM(b.narrative), 1, 1)) NOT BETWEEN 65 AND 90)  -- skip upper case first letters


  -- ************************************************************************************************************
  -- 02/17/21 RHE New code to handle mixing of new and old diagnoses on the same line, as done at VUMC but not UM
  -- ************************************************************************************************************
  DECLARE @ReplacementType varchar(6),
          @Phrase varchar(100),
          @SQL nvarchar(2048)
  DECLARE @ii smallint = 1
  DECLARE @iiMax smallint = (SELECT
    MAX(IDX)
  FROM #ECG_DiagnosesNoLongerPresent)

  WHILE @ii <= @iiMax
  BEGIN
    SET @ReplacementType = (SELECT
      ReplacementType
    FROM #ECG_DiagnosesNoLongerPresent
    WHERE idx = @ii)
    SET @Phrase = (SELECT
      Phrase
    FROM #ECG_DiagnosesNoLongerPresent
    WHERE idx = @ii)

    IF @ReplacementType IS NOT NULL
    BEGIN
      SET @SQL =
                CASE
                  WHEN @ReplacementType = 'After' THEN 'update #EKG
				set narrative =
				substring(narrative, 1, charindex(''' + @Phrase + ''',narrative)-1) 
				+
				case
					when charindex('' however '',narrative)>0 then
						case
							when charindex('' however '', narrative) > charindex(''' + @Phrase + ''',narrative)  
								then substring(Narrative, charindex('' however '',Narrative)+1,255)
							else ''''
						end
					when charindex('' but '',narrative)>0 then
						case
							when charindex('' but '', narrative) > charindex(''' + @Phrase + ''',narrative)  
								then substring(Narrative, charindex('' but '',Narrative)+1,255)
							else ''''
						end
					when charindex('' and '',narrative)>0 then
						case
							when charindex('' and '', narrative) > charindex(''' + @Phrase + ''',narrative)  
								then substring(Narrative, charindex('' and '',Narrative)+1,255)
							else ''''
						end

					else ''''
				end 
			where narrative like ''%' + @Phrase + '%''
			'

                  WHEN @ReplacementType = 'Before' THEN 'update #EKG
				set narrative =
				case
					when charindex('' however '',narrative)>0 or charindex('' but '',narrative)>0 or charindex('' and '',narrative)>0 then 
						case
							when (charindex('' but '', narrative) >0) AND (charindex('' but '', narrative) < charindex(''' + @Phrase + ''',narrative))   
								then substring(Narrative, 1, charindex('' but '',Narrative) -1) 	
							when (charindex('' however '', narrative)>0) AND (charindex('' however '', narrative) < charindex(''' + @Phrase + ''',narrative))   
								then substring(Narrative, 1, charindex('' however '',Narrative) -1) 
							when (charindex('' and '', narrative)>0) AND (charindex('' and '', narrative) < charindex(''' + @Phrase + ''',narrative))   
								then substring(Narrative, 1, charindex('' and '',Narrative) -1) 
							else ''''
						end
					else ''''
				end
				+
				substring(narrative, charindex(''' + @Phrase + ''',narrative) + len(''' + @Phrase + '''), 255 )
				from #EKG 
				where narrative like ''%' + @Phrase + '%''
				'
                  ELSE NULL
                END

      IF @SQL IS NOT NULL
      BEGIN
        EXEC (@SQL)
      END
    END
    SET @SQL = NULL
    SET @ii = @ii + 1
  END


  -- ***************************************************************************************************************
  -- ***************************************************************************************************************

  CREATE TABLE #EKG_Quantitative (
    ORDER_PROC_ID varchar(18),
    Line smallint,
    Narrative varchar(255),
    MatchString varchar(100),
    VariableName varchar(30),
    NumericValue int,
    StringValue varchar(1024)
  )

  -- ************************************
  --- determine the quantitative values
  -- ************************************
  TRUNCATE TABLE #EKG_Quantitative
  INSERT INTO #EKG_Quantitative
    SELECT
      ORDER_PROC_ID,
      Line,
      Narrative,
      MatchString,
      VariableName,
      CASE
        WHEN x.StringValue = 1 THEN NULL
        WHEN x.Allow0 = 1 THEN CONVERT(smallint, x.value)
        WHEN CONVERT(smallint, x.value) = 0 THEN NULL
        ELSE CONVERT(smallint, x.value)
      END AS NumericValue,
      CASE
        WHEN x.StringValue = 1 THEN Value
        ELSE NULL
      END AS StringValue
    FROM (SELECT
      ORDER_PROC_ID,
      Line,
      Narrative,
      b.MatchString,
      SUBSTRING(Narrative, CHARINDEX(b.matchstring, narrative) + offset, b.StringLength) AS value,
      c.ExcludeMatchString,
      CHARINDEX(c.excludematchstring, narrative) AS n,
      VariableName,
      Allow0,
      StringValue
    FROM #EKG a,
         #QuantitativeMatch b
         LEFT JOIN #MatchTypeExclusion c
           ON b.MatchType = c.MatchType
    WHERE ignore = 2			-- during preprocessing, rows with quantitative info are marked with a 2
    AND CHARINDEX(b.MatchString, a.Narrative) > 0
    --order by value desc -- ORDER_PROC_ID, MatchString
    ) x
    GROUP BY ORDER_PROC_ID,
             Line,
             Narrative,
             MatchString,
             VariableName,
             value,
             Allow0,
             StringValue
    HAVING SUM(n) = 0
    ORDER BY ORDER_PROC_ID, line
  -- select top 100 * from  #EKG_Quantitative

  -- extract the summary information for each order for the quantitative information
  TRUNCATE TABLE #EKGSummary
  INSERT INTO #EKGSummary (pat_id,
  ORDER_PROC_ID,
  EKGDate,
  Description)
    SELECT DISTINCT
      pat_id,
      ORDER_PROC_ID,
      Contact_Date,
      Description
    FROM #EKG

  -- apply the quantitative values
  DECLARE @TestReason varchar(30) = (SELECT
    MatchString
  FROM #QuantitativeMatch
  WHERE VariableName = 'Test_Reason')

  -- get the indication for the test and who reviewed it
  UPDATE #EKGSummary
  SET Indication = RTRIM(REPLACE(Narrative, @TestReason, ''))
  FROM #EKGSummary a
  INNER JOIN #EKG b
    ON a.order_proc_id = b.ORDER_PROC_ID
  WHERE CHARINDEX(@TestReason, Narrative) = 1


  -- if there is no test reason listed, just 'Test Reason :' set this to ;;
  UPDATE #EKGSummary
  SET Indication = ''
  WHERE Indication = @TestReason

  -- determine the person who read the ECG
  DECLARE @ReviewedBy varchar(30) = (SELECT
    MatchString
  FROM #QuantitativeMatch
  WHERE VariableName = 'EKG_Reader')

  UPDATE #EKGSummary
  SET Interpreter = StringValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE CHARINDEX(@ReviewedBy, Narrative) > 0

  -- determine the date of the evaluation
  UPDATE #EKGSummary
  SET InterpretationTime =
                          CASE
                            WHEN Interpreter LIKE '%/%/%:%' THEN CASE
                                WHEN ISDATE(REPLACE(SUBSTRING(Interpreter, CHARINDEX(')', Interpreter) + 5, 100), '"', '')) = 1 THEN REPLACE(SUBSTRING(Interpreter, CHARINDEX(')', Interpreter) + 5, 100), '"', '')
                                ELSE NULL
                              END
                            ELSE NULL
                          END

  -- fix the formatting of the prerson interpretting the study if there rare () around the name
  UPDATE #EKGSummary
  SET Interpreter =
                   CASE
                     WHEN CHARINDEX(')', Interpreter) > 0 THEN SUBSTRING(Interpreter, 1, CHARINDEX(')', Interpreter))
                     ELSE Interpreter
                   END

  UPDATE #EKGSummary
  SET QT = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'QT'
  UPDATE #EKGSummary
  SET QTc = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'QTc'
  UPDATE #EKGSummary
  SET QRS = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'QRS'
  UPDATE #EKGSummary
  SET PR = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'PR'
  UPDATE #EKGSummary
  SET V_Rate = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'V_Rate'
  UPDATE #EKGSummary
  SET A_Rate = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'A_Rate'
  UPDATE #EKGSummary
  SET P_Axis = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'P_Axis'
  UPDATE #EKGSummary
  SET R_Axis = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'R_Axis'
  UPDATE #EKGSummary
  SET T_Axis = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'T_Axis'

  -- select * from #EKGSummary

  -- ***************************************************************
  -- * Process the ECG narratives to determine the diagnoses
  -- * During preprocessing, rows with lines without diagnostic information are marked with a 1
  -- * and rows with quantitative infomration are marked with a 2.
  -- * ignore both
  -- ***************************************************************


  -- **************************************************
  -- get the sql statements to be applied for diagnostic purposes
  -- **************************************************

  -- drop table #DiagnosisEvaluation
  CREATE TABLE #SQL (
    idx int IDENTITY (1, 1),
    sql nvarchar(max)
  )

  TRUNCATE TABLE #SQL
  INSERT INTO #SQL
    SELECT
      sql
    FROM dbo.ECG_DiagnosisMatch
    WHERE sql IS NOT NULL


  -- to look at the SQL statements, execute the next commented line
  -- SELECT * FROM #SQL

  TRUNCATE TABLE #DiagnosisEvaluation
  DECLARE @SQL3 nvarchar(max)
  DECLARE @j int = 1
  DECLARE @jMax int = (SELECT
    MAX(idx)
  FROM #SQL)

  WHILE @j <= @jMax
  BEGIN
    SET @SQL3 = (SELECT
      sql
    FROM #SQL
    WHERE idx = @j)
    EXEC (@SQL3)
    SET @j = @j + 1
  END


  -- determine if a diagnosis is noted as possible normal variant, or only possibly likely
  TRUNCATE TABLE #DiagnosisEvaluationHedged

  INSERT INTO #DiagnosisEvaluationHedged
    SELECT
      a.*,
      b.*,
      CHARINDEX(b.phrase, a.Narrative)
    FROM #DiagnosisEvaluation a,
         #HedgePhrases b
    WHERE CHARINDEX(b.phrase, a.Narrative) > 0

  -- mark the rows where the diagnosis is uncertain
  UPDATE #DiagnosisEvaluationHedged
  SET DiagnosisUncertain = 1
  WHERE HedgeLocation < MatchLocation	-- hedge word has to before the match on the line.

  -- 01/22/21 RHE also mark diagnoses as hedged if the narrative ends with the phrase. 
  -- The cardiologists sometimes tack the hedge word on at the end of the diagnosis line
  UPDATE #DiagnosisEvaluationHedged
  SET DiagnosisUncertain = 1
  FROM #DiagnosisEvaluationHedged a
  INNER JOIN (SELECT
    a.IDX,
    a.Diagnosis,
    DiagnosisUncertain
  FROM #DiagnosisEvaluation a,
       #HedgePhrases b
  WHERE Narrative LIKE '%' + phrase) x
    ON a.idx = x.idx
    AND a.diagnosis = x.diagnosis
  WHERE a.DiagnosisUncertain = 0

  UPDATE #DiagnosisEvaluation
  SET DiagnosisUncertain = b.DiagnosisUncertain
  FROM #DiagnosisEvaluation a
  INNER JOIN #DiagnosisEvaluationHedged b
    ON a.idx = b.idx
    AND a.Diagnosis = b.diagnosis
  WHERE b.DiagnosisUncertain = 1


  -- ********************************************
  -- Save the results of the analysis
  -- ********************************************

  -- results of ECG narrative interpretation
  TRUNCATE TABLE dbo.ECG_ResultsDiagnostic
  INSERT INTO dbo.ECG_ResultsDiagnostic
    SELECT DISTINCT
      PAT_ID,
      ORDER_PROC_ID,
      ECGDate,
      NarrativeRaw,
      Narrative,
      Code,
      Diagnosis,
      DiagnosisUncertain
    FROM #DiagnosisEvaluation
    WHERE Ignore = 0
    ORDER BY ECGDate, PAT_ID



  -- results of the quantitative analysis
  TRUNCATE TABLE dbo.ECG_ResultsQuantitative
  INSERT INTO dbo.ECG_ResultsQuantitative
    SELECT
      *
    FROM #EKGSummary
    WHERE Interpreter IS NOT NULL



  -- ************************************************************
  -- *  This is for the evaluation of a narrative datset being used for testing and modification of the configuration files
  -- *  It is executed conditionally based on  @EvaluatePerformance = 1
  -- ***********************************************************************

  --DECLARE @EvaluatePerformance tinyint = 1 -- 1= generate the output for analysis of the processing;  0=skip the analysis (for production use)

  IF @EvaluatePerformance = 1
  BEGIN

    -- drop table #Performance
    CREATE TABLE #Performance (
      idx int IDENTITY (1, 1),
      Narrative varchar(1024),
      code varchar(4),
      Diagnosis varchar(100),
      MatchLocation int,
      HedgeCode char(3),
      HedgePhrase varchar(100),
      HedgeLocation int,
      Ignore tinyint,
      MergedCode varchar(30)
    )
    TRUNCATE TABLE #Performance
    INSERT INTO #Performance
      SELECT
        Narrative,
        Code,
        Diagnosis,
        MatchLocation,
        HedgeCode,
        HedgePhrase,
        HedgeLocation,
        Ignore,
        Code
      FROM #DiagnosisEvaluationHedged
      UNION
      SELECT
        a.Narrative,
        a.Code,
        a.Diagnosis,
        a.MatchLocation,
        NULL AS HedgeCode,
        NULL AS HedgePhrase,
        NULL AS HedgeLocation,
        Ignore,
        Code AS MergedCode
      FROM #DiagnosisEvaluation a
      WHERE RTRIM(a.narrative) + RTRIM(a.diagnosis)
      NOT IN (SELECT
        RTRIM(narrative) + RTRIM(diagnosis)
      FROM #DiagnosisEvaluationHedged)
      ORDER BY narrative, diagnosis, hedgephrase


    UPDATE #Performance
    SET MergedCode = mergedCode +
    CASE
      WHEN HedgeCode IS NULL THEN ''
      ELSE '-' + HedgeCode
    END
    WHERE HedgeLocation < MatchLocation

    -- get rid of the hedge pharse where there is no merged code; this means that the hedge phrase occurred after the diagnosis, and thus does not apply
    UPDATE #Performance
    SET HedgePhrase = ''
    WHERE MergedCode NOT LIKE '%-%'
    AND hedgephrase NOT LIKE '%normal variant%'   --- 1/18/21 When normal variant appears, it is after the diagnosis, so don't exclude as per code in previous line

    -- drop table #UniqueNarratives
    CREATE TABLE #UniqueNarratives (
      idx int IDENTITY (1, 1),
      Narrative varchar(1024),
      Ignore tinyint
    )
    TRUNCATE TABLE #UniqueNarratives
    INSERT INTO #UniqueNarratives
      SELECT
        narrative,
        ignore
      FROM #Performance
      ORDER BY narrative

    -- ****************************************************
    -- * # of EKGs analyzed 
    -- ****************************************************
    SELECT
      COUNT(x.order_proc_id) AS [# ECG Processed]
    FROM (SELECT DISTINCT
      order_proc_id
    FROM #EKG) x

    -- *******************************************************
    -- * Full list of distinct lines and the diagnoses matched
    -- * For a full evaluation of performance, one will need to check the
    -- * accuracy of the matching for each line.
    -- * Narrative lines matching to >1 diagnosis will be displayed multiple times,
    -- * 1x for each diagnosis
    -- * Configuration tables may need to be adjusted to improve accuracy
    -- *******************************************************

    TRUNCATE TABLE dbo.ECG_PerformanceAllNarratives
    INSERT INTO dbo.ECG_PerformanceAllNarratives
      SELECT
        x.idx,
        x.narrative,
        x.code,
        x.Diagnosis,
        x.HedgePhrase,
        y.n AS n
      FROM (SELECT DISTINCT
        b.idx,
        a.narrative,
        a.Code,
        a.Diagnosis,
        ISNULL(HedgePhrase, '') AS HedgePhrase
      FROM #Performance a
      INNER JOIN #UniqueNarratives b
        ON a.Narrative = b.narrative
      WHERE a.ignore = 0
      --order by narrative, a.diagnosis, HedgePhrase
      ) x
      LEFT JOIN (SELECT
        narrative,
        COUNT(narrative) AS n
      FROM #EKG
      GROUP BY narrative) y
        ON x.narrative = y.narrative
      ORDER BY x.narrative, x.diagnosis, x.HedgePhrase

    -- For evaluation of the algoritm performance among all EKGs
    -- select * from dbo.ECG_PerformanceAllNarratives where code <> 927 order by narrativeID, code


    -- *****************************************************************
    -- * List the diagnosis matches for each distinct narrative
    -- * write the output to the table dbo.ECG_DiscretePerformance
    -- * Export to Excel for checking and possible modification of diagnosis matching
    -- *****************************************************************
    TRUNCATE TABLE dbo.ECG_PerformanceDiscreteNarratives
    INSERT INTO dbo.ECG_PerformanceDiscreteNarratives
      SELECT
        Narrative,
        Code,
        Diagnosis,
        HedgePhrase,
        SUM(n) AS n
      FROM dbo.ECG_PerformanceAllNarratives
      GROUP BY Narrative,
               Code,
               Diagnosis,
               HedgePhrase
      ORDER BY Narrative,
      Diagnosis,
      HedgePhrase

    -- For evaluation of the algorithm performance among distinct narratives
    -- select * from dbo.ECG_PerformanceDiscreteNarratives where narrative like '%.'
    -- select distinct narrative, code, diagnosis from dbo.ECG_PerformanceDiscreteNarratives where code<900  order by narrative, diagnosis

    -- *******************************************************
    -- * Distinct narrative lines that did not match any diagnosis
    -- * the counts of the the distinct lines are displayed
    -- * may need to adjust the configuration tables to classify lines without matches
    -- * suggest ignoring lines that are only represented once in the database
    -- * Lines with no diagnostoc information should be ignored
    -- *******************************************************
    TRUNCATE TABLE dbo.ECG_PerformanceNarrativesWithoutDiagnosis
    INSERT INTO dbo.ECG_PerformanceNarrativesWithoutDiagnosis
      SELECT
        a.Narrative,
        COUNT(a.narrative) AS n
      FROM #EKG a
      LEFT JOIN dbo.ECG_PerformanceAllNarratives b
        ON a.narrative = b.narrative
      WHERE a.Ignore = 0
      AND b.narrative IS NULL
      AND a.narrative <> ''
      GROUP BY a.narrative
      ORDER BY n DESC


    UPDATE dbo.ecg_narratives
    SET narrative = ''
    FROM dbo.ECG_Narratives a
    INNER JOIN (SELECT
      a.ORDER_PROC_ID
    --,a.NarrativeRaw
    --,a.Narrative
    FROM dbo.ECG_Narratives a
    INNER JOIN #EKG b
      ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
    WHERE b.narrative = '') x
      ON a.ORDER_PROC_ID = x.ORDER_PROC_ID




    -- *************************************************************
    -- 	Results or evaluation of accuracy of matchinng of diagnoses
    -- *************************************************************
    SELECT
      'Results of matching all distinct narratives to diagnoses' AS 'Output Table'
    /*
    select	
    ORDER_PROC_ID,	
    NarrativeRaw,	
    Narrative,	
    Code,	
    Diagnosis,
    DiagnosisUncertain
    from dbo.ECG_ResultsDiagnostic 
    UNION
    select 
    a.ORDER_PROC_ID	,
    a.NarrativeRaw,	
    a.Narrative as Narrative	,
    null as Code,	
    null as Diagnosis,
    null as DiagnosisUncertain
    from dbo.ECG_Narratives a left join dbo.ECG_ResultsDiagnostic b
    on a.ORDER_PROC_ID = b.order_proc_id
    where b.ORDER_PROC_ID is null
    ORDER by code --ORDER_PROC_ID, Narrative, Code
    */

    SELECT
      Narrative,
      Code,
      Diagnosis,
      HedgePhrase,
      n
    FROM dbo.ECG_PerformanceDiscreteNarratives
    ORDER BY Narrative, Diagnosis


    -- *************************************************************
    -- 	Narratives not matching any diagnosis
    -- *************************************************************
    SELECT
      'Narratives without a diagnostic match' AS 'Output Table'
    SELECT
      Narrative,
      n
    FROM dbo.ECG_PerformanceNarrativesWithoutDiagnosis


    -- *************************************************************
    -- 	Results of the quantitative matching
    -- *************************************************************
    SELECT
      'Results of the quantitative matching' AS 'Output Table'
    SELECT
      *
    FROM dbo.ECG_ResultsQuantitative


  END


  IF OBJECT_ID('tempdb.dbo.#DiagnosisExclusions') IS NOT NULL
    DROP TABLE #DiagnosisExclusions
  IF OBJECT_ID('tempdb.dbo.#HedgePhrases') IS NOT NULL
    DROP TABLE #HedgePhrases
  IF OBJECT_ID('tempdb.dbo.#QuantitativeMatch') IS NOT NULL
    DROP TABLE #QuantitativeMatch
  IF OBJECT_ID('tempdb.dbo.#MatchTypeExclusion') IS NOT NULL
    DROP TABLE #MatchTypeExclusion
  IF OBJECT_ID('tempdb.dbo.#EKG') IS NOT NULL
    DROP TABLE #EKG
  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosesNoLongerPresent') IS NOT NULL
    DROP TABLE #ECG_DiagnosesNoLongerPresent
  IF OBJECT_ID('tempdb.dbo.#DiagnosisEvaluation') IS NOT NULL
    DROP TABLE #DiagnosisEvaluation
  IF OBJECT_ID('tempdb.dbo.#EKG_Quantitative') IS NOT NULL
    DROP TABLE #EKG_Quantitative
  IF OBJECT_ID('tempdb.dbo.#EKGSummary') IS NOT NULL
    DROP TABLE #EKGSummary
  IF OBJECT_ID('tempdb.dbo.#SQL') IS NOT NULL
    DROP TABLE #SQL
  IF OBJECT_ID('tempdb.dbo.#DiagnosisEvaluationHedged') IS NOT NULL
    DROP TABLE #DiagnosisEvaluationHedged
  IF OBJECT_ID('tempdb.dbo.#Performance') IS NOT NULL
    DROP TABLE #Performance
  IF OBJECT_ID('tempdb.dbo.#UniqueNarratives') IS NOT NULL
    DROP TABLE #UniqueNarratives


