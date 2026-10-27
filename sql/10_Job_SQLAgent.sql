/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 10_Job_SQLAgent.sql
   Rôle        : Crée un job SQL Server Agent qui lance chaque matin à 06:00
                 le master package DÉPLOYÉ dans le catalogue SSISDB.

   PRÉ-REQUIS (phase 5 de la ROADMAP) :
     1. Catalogue SSISDB créé (SSMS > Integration Services Catalogs > Create Catalog)
     2. Projet SSIS déployé dans SSISDB, dossier "DWH_Suisse"
        (Visual Studio > clic droit sur le projet > Deploy)
     3. Service "SQL Server Agent" démarré
     4. Script 09_Securite.sql exécuté

   NE PAS exécuter ce script avant ces étapes : il n'est pas lancé par
   Deploy-Database.ps1.
   Ré-exécutable : OUI (supprime et recrée le job)
   ============================================================================= */
USE msdb;
GO

DECLARE @JobName  SYSNAME       = N'DWH Suisse - Chargement quotidien';
DECLARE @Server   NVARCHAR(128) = @@SERVERNAME;
DECLARE @Command  NVARCHAR(MAX) =
      N'/ISSERVER "\"\SSISDB\DWH_Suisse\DWH_Suisse_ETL\00_MASTER.dtsx\"" '
    + N'/SERVER "\"' + @Server + N'\"" '
    + N'/Par "\"$ServerOption::LOGGING_LEVEL(Int16)\"";1 '
    + N'/Par "\"$ServerOption::SYNCHRONIZED(Boolean)\"";True '
    + N'/CALLERINFO SQLAGENT /REPORTING E';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
    EXEC msdb.dbo.sp_delete_job @job_name = @JobName;

EXEC msdb.dbo.sp_add_job
     @job_name    = @JobName,
     @description = N'Télécharge les données CFF/SBB + météo, alimente ODS > STG > DWH puis traite le cube.',
     @enabled     = 1;

EXEC msdb.dbo.sp_add_jobstep
     @job_name          = @JobName,
     @step_name         = N'Master package',
     @subsystem         = N'SSIS',
     @command           = @Command,
     @on_success_action = 1,   -- quitter en signalant le succès
     @on_fail_action    = 2;   -- quitter en signalant l'échec

EXEC msdb.dbo.sp_add_jobschedule
     @job_name          = @JobName,
     @name              = N'Chaque jour 06:00',
     @freq_type         = 4,      -- quotidien
     @freq_interval     = 1,
     @active_start_time = 60000;  -- 06:00:00

EXEC msdb.dbo.sp_add_jobserver @job_name = @JobName, @server_name = N'(local)';

PRINT N'10 - Job SQL Agent créé : ' + @JobName;
GO
