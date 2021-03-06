/*
ECG_LoadNarratives_Epic

Description:
	Load the ECG narratives into the table dbo.ECG_Narratives FROM Epic
	If using an EHR other than Epic, the table dbo.ECG_Narratives needs to be loaded using code for that system or from a tab delimited text file
	using the stored procedure ECG_LoadNarratives_Text

Author: Richard H. Epstein, MD
Copyright (C) 2020


IMPORTANT NOTES: 
	1. Modify the values PROC_ID as determined FROM the stored procedure ECG_Epic_Find_PROC_ID
	2. Modify the values of @StartDate and @EndDate to SELECT the desired range of ECG narratives to process
	3. The NarrativeRaw will be processed subsequently by the stored procedure ECG_PreprocessNarratives to create the Narrative field
 
Syntax:
	EXEC [dbo].[ECG_LoadNarratives]									-- load ECG narrative from the previous 60 days
	EXEC [dbo].[ECG_LoadNarratives] '2019-01-01', '2019-12-31'		-- load ECG narratives from the specified date range


Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding



*/


--/*
CREATE PROC [dbo].[ECG_LoadNarratives_Epic] @StartDate datetime = NULL, @EndDate datetime = NULL
AS

  SET NOCOUNT ON

  --*/

-- NOTE: Change CLARITY to the database on your system where the Clarity tables are stored


  /*  -- uncomment to run manually and specifiy the date values
  DECLARE @StartDate datetime		= '2019-01-01'
  DECLARE @EndDate datetime		= '2019-12-31'
  --*/

  -- if no date parameter is supplied, default to the most recent 30 days
  IF @EndDate IS NULL
  BEGIN
    SET @EndDate = GETDATE()
  END							-- default to current date if null
  IF @StartDate IS NULL
  BEGIN
    SET @StartDate = DATEADD(dd, -60, @EndDate)
  END					-- default to 60 days before @EndDate if null



  -- Retrieve the ECG narratives into a database table after clearing the data in that table
  TRUNCATE TABLE dbo.ECG_Narratives
  INSERT INTO dbo.ECG_Narratives
    SELECT
      pat_id,
      a.ORDER_PROC_ID,
      b.contact_date,
      a.description,
      line,
      NULL AS Narrative,
      RTRIM(LTRIM(ISNULL(Narrative, ''))) AS NarrativeRaw,  -- get rid of any leading or trailing spaces on each line
      0 AS ignore
    FROM CLARITY.DBO.ORDER_PROCx a WITH (NOLOCK)
    INNER JOIN CLARITY.DBO.ORDER_NARRATIVE b WITH (NOLOCK)
      ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
    WHERE
    -- NOTE: Modify the list of PROC_ID and ORDER_TYPE_C below to correspond to your version of Epic
    (
    ORDER_TYPE_C IN (28, 62)
    AND PROC_ID IN (509, 21000000009, 92916, 515, 178113)
    )
    AND CONTACT_DATE BETWEEN @StartDate AND @EndDate
    ORDER BY a.pat_id,
    a.ORDER_PROC_ID,
    b.line

