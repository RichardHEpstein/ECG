/* 
dbo.Epic_Find_PROC_ID_ECGinLabs

Copyringt (C) 2021
Author: Ricahrd H. Epstein, MD

Determine the locations of the ECG diagnosis results for Epic implementations where these are stored as labs
rather than narratives



Change Control
Date  	Ver		By		Note
02/08/21	1.00	RHE		Initial coding for VUMC 


*/

--/*
CREATE PROC [dbo].[Epic_Find_PROC_ID_ECGinLabs]
AS
  --*/



  -- *****************************************************************************
  -- Step 1. This will list all the PROC_ID potentially related to an EKG
  -- Note the PROC_ID's that are related to a 12-lead EKG for the next section
  -- ******************************************************************************
  SELECT
    PROC_ID,
    Description,
    COUNT(proc_id) AS n
  FROM clarity.dbo.order_proc WITH (NOLOCK)
  WHERE Description LIKE '%e[ck]g%'
  GROUP BY PROC_ID,
           DESCRIPTION
  ORDER BY n DESC


  -- *****************************************************************************
  -- Step 2. Get the component ID's associated with the PROC_ID related to 12 lead ECG impressions
  -- where the results are in the lab table
  -- Replace the value of the PROC_ID with the value from your system
  -- For example, at VUMC the component names will be ECG Impresion and ECG Severity T
  -- Note the component ID
  -- *****************************************************************************
  SELECT DISTINCT
    a.proc_ID,
    b.COMPONENT_ID,
    c.External_Name
  FROM clarity.dbo.ORDER_PROC a WITH (NOLOCK)
  INNER JOIN clarity.dbo.ORDER_RESULTS b WITH (NOLOCK)
    ON a.order_proc_id = b.order_proc_id
  INNER JOIN clarity.dbo.CLARITY_COMPONENT c
    ON b.COMPONENT_ID = c.COMPONENT_ID
  WHERE a.PROC_ID IN (509, 21000000009)
  AND c.external_name LIKE '%e[ck]g%'

  -- *****************************************************************************
  -- Step 3. get the distinct narrative results to evaluate for ECG NLP config table changes
  -- Substitute the values of the PROC_IDs and the COMPONENT_IDs that have the 
  -- ECG Severity T and ECG Impression components
  -- this will pull all the distinct narratives from 1/1/2019
  -- ******************************************************************************
  SELECT
    ORD_VALUE AS Narrative,
    COUNT(ord_VALUE) AS n
  FROM clarity.dbo.ORDER_PROC a WITH (NOLOCK)
  INNER JOIN clarity.dbo.ORDER_RESULTS b
    ON a.order_proc_id = b.order_proc_id
  WHERE PROC_ID IN (174895)
  AND COMPONENT_ID IN (11603, 11628)
  AND ORDER_INST > '2019-01-01'
  GROUP BY ord_value
  ORDER BY n DESC


