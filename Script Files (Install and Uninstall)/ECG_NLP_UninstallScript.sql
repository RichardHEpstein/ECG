/*
Uninstall script for the ECG NLP processing system

Copyright (C) 2021 Richard H. Epstein, MD
System may be used or modified for non-commerical applications with acknowledgment of the source of the code
Commercial use is prohibited without licensure from the author


Note:  This script will remove the ECG NLP tables and stored procedures from the database
		It should be executed from a query window in the database where the files have been installed

Acknowledgments: SQL CODE was beautified from the original stored procedures using  https://sql-format.com/

Version Control
Date		version		by		Notes
06/30/21	1.01		RHE		Original coding


*/

SELECT
  'Dropping ECG NLP tables' AS Message

-- remove the tables
IF OBJECT_ID('[dbo].[ECG_DiagnosesNoLongerPresent]') IS NOT NULL
  DROP TABLE [dbo].[ECG_DiagnosesNoLongerPresent]
IF OBJECT_ID('[dbo].[ECG_DiagnosisExclusions]') IS NOT NULL
  DROP TABLE [dbo].[ECG_DiagnosisExclusions]
IF OBJECT_ID('[dbo].[ECG_DiagnosisMatch]') IS NOT NULL
  DROP TABLE [dbo].[ECG_DiagnosisMatch]
IF OBJECT_ID('[dbo].[ECG_HedgePhrases]') IS NOT NULL
  DROP TABLE [dbo].[ECG_HedgePhrases]
IF OBJECT_ID('[dbo].[ECG_MatchTypeExclusion]') IS NOT NULL
  DROP TABLE [dbo].[ECG_MatchTypeExclusion]
IF OBJECT_ID('[dbo].[ECG_Misspellings]') IS NOT NULL
  DROP TABLE [dbo].[ECG_Misspellings]
IF OBJECT_ID('[dbo].[ECG_Narratives]') IS NOT NULL
  DROP TABLE [dbo].[ECG_Narratives]
IF OBJECT_ID('[dbo].[ECG_PerformanceAllNarratives]') IS NOT NULL
  DROP TABLE [dbo].[ECG_PerformanceAllNarratives]
IF OBJECT_ID('[dbo].[ECG_PerformanceDiscreteNarrativeS]') IS NOT NULL
  DROP TABLE [dbo].[ECG_PerformanceDiscreteNarrativeS]
IF OBJECT_ID('[dbo].[ECG_PerformanceNarrativesWithoutDiagnosis]') IS NOT NULL
  DROP TABLE [dbo].[ECG_PerformanceNarrativesWithoutDiagnosis]
IF OBJECT_ID('[dbo].[ECG_QuantitativeMatch]') IS NOT NULL
  DROP TABLE [dbo].[ECG_QuantitativeMatch]
IF OBJECT_ID('[dbo].[ECG_ResultsDiagnostic]') IS NOT NULL
  DROP TABLE [dbo].[ECG_ResultsDiagnostic]
IF OBJECT_ID('[dbo].[ECG_ResultsQuantitative]') IS NOT NULL
  DROP TABLE [dbo].[ECG_ResultsQuantitative]
IF OBJECT_ID('[dbo].[ECG_Spelling]') IS NOT NULL
  DROP TABLE [dbo].[ECG_Spelling]
IF OBJECT_ID('[dbo].[ECG_SpellingSentencesExcluded]') IS NOT NULL
  DROP TABLE [dbo].[ECG_SpellingSentencesExcluded]
IF OBJECT_ID('[dbo].[ECG_FolderLocations]') IS NOT NULL
  DROP TABLE [dbo].[ECG_FolderLocations]


SELECT
  'Dropping ECG NLP stored procedures' AS Message
-- remove the stored procedures
IF OBJECT_ID('dbo.ECG_CreateTablesForNLProcessing') IS NOT NULL
  DROP PROC dbo.ECG_CreateTablesForNLProcessing
IF OBJECT_ID('dbo.ECG_DetermineEpicECGIdentifiers') IS NOT NULL
  DROP PROC dbo.ECG_DetermineEpicECGIdentifiers
IF OBJECT_ID('dbo.ECG_IdentifyMisspelledWords') IS NOT NULL
  DROP PROC dbo.ECG_IdentifyMisspelledWords
IF OBJECT_ID('dbo.ECG_LoadNarratives_Epic') IS NOT NULL
  DROP PROC dbo.ECG_LoadNarratives_Epic
IF OBJECT_ID('dbo.ECG_LoadNarratives_Text') IS NOT NULL
  DROP PROC dbo.ECG_LoadNarratives_Text
IF OBJECT_ID('dbo.ECG_PreProcessNarratives') IS NOT NULL
  DROP PROC dbo.ECG_PreProcessNarratives
IF OBJECT_ID('dbo.ECG_ProcessNarratives') IS NOT NULL
  DROP PROC dbo.ECG_ProcessNarratives
IF OBJECT_ID('dbo.Epic_Find_PROC_ID_ECGinLabs') IS NOT NULL
  DROP PROC dbo.Epic_Find_PROC_ID_ECGinLabs

SELECT
  'The ECG NLP system has been removed from the database' AS Message