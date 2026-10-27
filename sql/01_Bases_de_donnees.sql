/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 01_Bases_de_donnees.sql
   Rôle        : Crée les 4 bases de données du projet et leurs schémas.
   Ré-exécutable : OUI (ne recrée rien si la base existe déjà)

   Les 4 bases :
     CH_ADMIN : pilotage (journal des lots, des étapes, des fichiers chargés)
     CH_ODS   : données BRUTES, telles que reçues des sources (tout en texte)
     CH_STG   : données TYPÉES et NETTOYÉES (zone de travail, vidée à chaque lot)
     CH_DWH   : entrepôt final en étoile (dimensions + faits), source du cube
   ============================================================================= */
USE master;
GO

IF DB_ID(N'CH_ADMIN') IS NULL CREATE DATABASE CH_ADMIN;
GO
IF DB_ID(N'CH_ODS')   IS NULL CREATE DATABASE CH_ODS;
GO
IF DB_ID(N'CH_STG')   IS NULL CREATE DATABASE CH_STG;
GO
IF DB_ID(N'CH_DWH')   IS NULL CREATE DATABASE CH_DWH;
GO

/* Mode de récupération SIMPLE : adapté à un entrepôt rechargé par lots
   (le journal des transactions ne grossit pas indéfiniment). */
ALTER DATABASE CH_ADMIN SET RECOVERY SIMPLE;
ALTER DATABASE CH_ODS   SET RECOVERY SIMPLE;
ALTER DATABASE CH_STG   SET RECOVERY SIMPLE;
ALTER DATABASE CH_DWH   SET RECOVERY SIMPLE;
GO

/* ---------- Schémas ---------- */
USE CH_ADMIN;
GO
IF SCHEMA_ID(N'etl') IS NULL EXEC (N'CREATE SCHEMA etl AUTHORIZATION dbo;');
GO

USE CH_ODS;
GO
IF SCHEMA_ID(N'ods') IS NULL EXEC (N'CREATE SCHEMA ods AUTHORIZATION dbo;');
GO

USE CH_STG;
GO
IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg AUTHORIZATION dbo;');
GO

USE CH_DWH;
GO
IF SCHEMA_ID(N'dim')  IS NULL EXEC (N'CREATE SCHEMA dim  AUTHORIZATION dbo;');  -- dimensions (axes d'analyse)
IF SCHEMA_ID(N'fact') IS NULL EXEC (N'CREATE SCHEMA fact AUTHORIZATION dbo;');  -- faits (mesures)
IF SCHEMA_ID(N'etl')  IS NULL EXEC (N'CREATE SCHEMA etl  AUTHORIZATION dbo;');  -- procédures de chargement
IF SCHEMA_ID(N'cube') IS NULL EXEC (N'CREATE SCHEMA cube AUTHORIZATION dbo;');  -- vues lues par le cube SSAS
GO

PRINT N'01 - Bases et schémas : OK';
