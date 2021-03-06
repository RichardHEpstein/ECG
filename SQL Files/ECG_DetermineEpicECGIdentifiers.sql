/*
ECG_DetermineEpicECGIdentifiers

Determine the ORDER_TYPE_C and the PROC_ID for the ECG narratives in Epic

The values for the ORDER_TYPE_C adn PROC_ID need to be applied to the PROC ECG_LoadNarratives


Modify the proc as needed to select the ECG's to include in the processing

Author: Richard H. Epstein, MD
Copyright (C) 2020

Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding


*/


--*/
CREATE PROC [dbo].[ECG_DetermineEpicECGIdentifiers]
AS
  --*/

  SET NOCOUNT ON

  -- NOTE: Change the name of the database from CLARITY to the location on your system

  -- **********************************************************
  -- * 1. Determine the order_type_c of the ECG tests in Epic
  -- **********************************************************
  SELECT
    *
  FROM CLARITY.[dbo].[ZC_ORDER_TYPE] WITH (NOLOCK)
  WHERE name LIKE '%e[ck]g%'

  -- **********************************************************
  -- * 2. Determine the proc_id of the potential ECG narratives
  -- **********************************************************
  SELECT
    PROC_ID,
    Description,
    COUNT(PROC_ID) AS n
  FROM CLARITY.dbo.ORDER_PROC WITH (NOLOCK)
  WHERE ORDER_TYPE_C IN (28, 62)  -- modify this list from the previous step
  AND
  (
  Description LIKE '%e[ck]g%'
  OR Description LIKE '%electrocard%'
  )
  GROUP BY PROc_ID,
           DESCRIPTION
  ORDER BY n DESC

  -- *************************************************************
  -- * 3. Check the PROC_IDs from step 2 above to determine which are 
  -- * actually ECG narratives from 12 lead ECG reports
  -- ************************************************************
  SELECT TOP 100
    a.ORDER_PROC_ID,
    a.description,
    line,
    ISNULL(Narrative, '') AS Narrative
  FROM CLARITY.dbo.order_proc a WITH (NOLOCK)
  INNER JOIN CLARITY.dbo.ORDER_NARRATIVE b WITH (NOLOCK)
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE PROC_ID IN (509)					-- modify this number by the candidate PROC_IDs from step 2, above
  ORDER BY PROC_ID,
  a.ORDER_PROC_ID,
  b.line



