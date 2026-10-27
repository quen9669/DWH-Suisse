/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 02_ADMIN.sql
   Base        : CH_ADMIN
   Rôle        : Tables et procédures de PILOTAGE de l'alimentation.
                 - etl.Batch   : un "lot" = une exécution complète du master package
                 - etl.StepLog : chaque étape d'un lot (durée, lignes, statut)
                 - etl.FileLog : chaque fichier source chargé (évite les doublons,
                                 permet la reprise après incident)
   Ré-exécutable : OUI
   ============================================================================= */
USE CH_ADMIN;
GO

/* ---------------------------------------------------------------------------
   Tables
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'etl.Batch', N'U') IS NULL
CREATE TABLE etl.Batch
(
    BatchId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Batch PRIMARY KEY,
    PackageName   NVARCHAR(200)     NOT NULL,
    BatchStart    DATETIME2(0)      NOT NULL CONSTRAINT DF_Batch_Start  DEFAULT (SYSDATETIME()),
    BatchEnd      DATETIME2(0)      NULL,
    [Status]      NVARCHAR(20)      NOT NULL CONSTRAINT DF_Batch_Status DEFAULT (N'En cours'),
    LaunchedBy    NVARCHAR(128)     NOT NULL CONSTRAINT DF_Batch_User   DEFAULT (SUSER_SNAME()),
    ErrorMessage  NVARCHAR(MAX)     NULL,
    CONSTRAINT CK_Batch_Status CHECK ([Status] IN (N'En cours', N'Succès', N'Échec', N'Abandonné'))
);
GO

/* Lot n°0 réservé : un package enfant exécuté SEUL (hors master) reçoit
   BatchId = 0 ; ses étapes sont journalisées sous ce lot. */
IF NOT EXISTS (SELECT 1 FROM etl.Batch WHERE BatchId = 0)
BEGIN
    SET IDENTITY_INSERT etl.Batch ON;
    INSERT INTO etl.Batch (BatchId, PackageName, BatchEnd, [Status])
    VALUES (0, N'Exécutions manuelles (hors master)', SYSDATETIME(), N'Succès');
    SET IDENTITY_INSERT etl.Batch OFF;
END;
GO

IF OBJECT_ID(N'etl.StepLog', N'U') IS NULL
CREATE TABLE etl.StepLog
(
    StepId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_StepLog PRIMARY KEY,
    BatchId       INT               NOT NULL CONSTRAINT FK_StepLog_Batch REFERENCES etl.Batch (BatchId),
    StepName      NVARCHAR(200)     NOT NULL,
    StepStart     DATETIME2(0)      NOT NULL CONSTRAINT DF_StepLog_Start  DEFAULT (SYSDATETIME()),
    StepEnd       DATETIME2(0)      NULL,
    DurationSec   AS (DATEDIFF(SECOND, StepStart, StepEnd)),
    [Status]      NVARCHAR(20)      NOT NULL CONSTRAINT DF_StepLog_Status DEFAULT (N'En cours'),
    RowsRead      BIGINT            NULL,
    RowsInserted  BIGINT            NULL,
    RowsUpdated   BIGINT            NULL,
    RowsDeleted   BIGINT            NULL,
    RowsRejected  BIGINT            NULL,
    [Message]     NVARCHAR(MAX)     NULL,
    CONSTRAINT CK_StepLog_Status CHECK ([Status] IN (N'En cours', N'Succès', N'Échec', N'Avertissement'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_StepLog_BatchId')
    CREATE INDEX IX_StepLog_BatchId ON etl.StepLog (BatchId);
GO

IF OBJECT_ID(N'etl.FileLog', N'U') IS NULL
CREATE TABLE etl.FileLog
(
    FileLogId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FileLog PRIMARY KEY,
    SourceType    NVARCHAR(30)      NOT NULL,   -- ISTDATEN / METEO
    [FileName]    NVARCHAR(260)     NOT NULL,
    BatchIdOds    INT               NOT NULL,
    OdsLoadDtm    DATETIME2(0)      NOT NULL CONSTRAINT DF_FileLog_Ods DEFAULT (SYSDATETIME()),
    RowsOds       BIGINT            NULL,
    [Status]      NVARCHAR(20)      NOT NULL CONSTRAINT DF_FileLog_Status DEFAULT (N'ODS_OK'),
    BatchIdDwh    INT               NULL,
    DwhLoadDtm    DATETIME2(0)      NULL,
    CONSTRAINT UQ_FileLog UNIQUE (SourceType, [FileName]),
    CONSTRAINT CK_FileLog_Status CHECK ([Status] IN (N'ODS_OK', N'DWH_OK'))
);
GO

/* ---------------------------------------------------------------------------
   Procédures : lots
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Batch_Start
    @PackageName NVARCHAR(200)
AS
/* Ouvre un nouveau lot et renvoie son identifiant (BatchId).
   Les lots restés "En cours" (ex. exécution interrompue dans Visual Studio)
   sont d'abord marqués "Abandonné". */
BEGIN
    SET NOCOUNT ON;

    UPDATE etl.Batch
       SET [Status] = N'Abandonné', BatchEnd = SYSDATETIME()
     WHERE [Status] = N'En cours' AND BatchId > 0;

    INSERT INTO etl.Batch (PackageName) VALUES (@PackageName);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS BatchId;
END;
GO

CREATE OR ALTER PROCEDURE etl.usp_Batch_End
    @BatchId      INT,
    @Status       NVARCHAR(20),
    @ErrorMessage NVARCHAR(MAX) = NULL,
    @SourceName   NVARCHAR(200) = NULL   -- tâche SSIS en erreur (System::SourceName)
AS
/* Clôture un lot. Peut être appelée plusieurs fois en cas d'erreurs multiples :
   un lot en "Échec" le reste, les messages d'erreur sont concaténés. */
BEGIN
    SET NOCOUNT ON;

    IF @SourceName IS NOT NULL AND @ErrorMessage IS NOT NULL
        SET @ErrorMessage = N'[' + @SourceName + N'] ' + @ErrorMessage;

    UPDATE etl.Batch
       SET BatchEnd     = SYSDATETIME(),
           [Status]     = CASE WHEN [Status] = N'Échec' THEN N'Échec' ELSE @Status END,
           ErrorMessage = CASE WHEN @ErrorMessage IS NULL THEN ErrorMessage
                               WHEN ErrorMessage IS NULL THEN @ErrorMessage
                               ELSE ErrorMessage + NCHAR(13) + NCHAR(10) + @ErrorMessage END
     WHERE BatchId = @BatchId;

    -- Les étapes encore "En cours" d'un lot en échec sont marquées en échec.
    IF @Status = N'Échec'
        UPDATE etl.StepLog
           SET [Status] = N'Échec', StepEnd = SYSDATETIME()
         WHERE BatchId = @BatchId AND [Status] = N'En cours';
END;
GO

/* ---------------------------------------------------------------------------
   Procédures : étapes
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Step_Start
    @BatchId  INT,
    @StepName NVARCHAR(200),
    @StepId   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO etl.StepLog (BatchId, StepName) VALUES (@BatchId, @StepName);
    SET @StepId = CAST(SCOPE_IDENTITY() AS INT);

    SELECT @StepId AS StepId;  -- lu par SSIS (Execute SQL Task, résultat "Ligne unique")
END;
GO

CREATE OR ALTER PROCEDURE etl.usp_Step_End
    @StepId       INT,
    @Status       NVARCHAR(20)  = N'Succès',
    @RowsRead     BIGINT        = NULL,
    @RowsInserted BIGINT        = NULL,
    @RowsUpdated  BIGINT        = NULL,
    @RowsDeleted  BIGINT        = NULL,
    @RowsRejected BIGINT        = NULL,
    @Message      NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE etl.StepLog
       SET StepEnd      = SYSDATETIME(),
           [Status]     = @Status,
           RowsRead     = @RowsRead,
           RowsInserted = @RowsInserted,
           RowsUpdated  = @RowsUpdated,
           RowsDeleted  = @RowsDeleted,
           RowsRejected = @RowsRejected,
           [Message]    = @Message
     WHERE StepId = @StepId;
END;
GO

CREATE OR ALTER PROCEDURE etl.usp_Step_End_Files
    @StepId     INT,
    @BatchId    INT,
    @SourceType NVARCHAR(30)
AS
/* Clôture une étape de chargement de fichiers : le nombre de lignes est la
   somme des fichiers chargés par ce lot (lu dans etl.FileLog). */
BEGIN
    SET NOCOUNT ON;

    DECLARE @Rows BIGINT, @Files INT;
    SELECT @Rows = COALESCE(SUM(RowsOds), 0), @Files = COUNT(*)
      FROM etl.FileLog
     WHERE BatchIdOds = @BatchId AND SourceType = @SourceType;

    DECLARE @Msg NVARCHAR(200) = CONCAT(@Files, N' fichier(s) ', @SourceType, N' chargé(s)');
    EXEC etl.usp_Step_End @StepId = @StepId, @Status = N'Succès', @RowsInserted = @Rows, @Message = @Msg;
END;
GO

/* ---------------------------------------------------------------------------
   Procédures : fichiers
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_File_Register
    @SourceType NVARCHAR(30),
    @FileName   NVARCHAR(260),
    @BatchId    INT,
    @RowsOds    BIGINT
AS
/* Enregistre (ou ré-enregistre) un fichier chargé dans l'ODS.
   Statut ODS_OK = "reçu, pas encore intégré à l'entrepôt". */
BEGIN
    SET NOCOUNT ON;

    MERGE etl.FileLog AS t
    USING (SELECT @SourceType AS SourceType, @FileName AS [FileName]) AS s
       ON t.SourceType = s.SourceType AND t.[FileName] = s.[FileName]
    WHEN MATCHED THEN
        UPDATE SET BatchIdOds = @BatchId, OdsLoadDtm = SYSDATETIME(), RowsOds = @RowsOds,
                   [Status] = N'ODS_OK', BatchIdDwh = NULL, DwhLoadDtm = NULL
    WHEN NOT MATCHED THEN
        INSERT (SourceType, [FileName], BatchIdOds, RowsOds)
        VALUES (@SourceType, @FileName, @BatchId, @RowsOds);
END;
GO

CREATE OR ALTER PROCEDURE etl.usp_File_SetDwhLoaded
    @SourceType NVARCHAR(30),
    @BatchId    INT
AS
/* Appelée après le chargement réussi des faits : les fichiers en attente
   sont marqués comme intégrés à l'entrepôt (DWH_OK). */
BEGIN
    SET NOCOUNT ON;

    UPDATE etl.FileLog
       SET [Status] = N'DWH_OK', BatchIdDwh = @BatchId, DwhLoadDtm = SYSDATETIME()
     WHERE SourceType = @SourceType AND [Status] = N'ODS_OK';
END;
GO

/* ---------------------------------------------------------------------------
   Vues de suivi (à ouvrir dans SSMS pour voir ce qui s'est passé)
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW etl.vw_Suivi_Lots
AS
SELECT TOP (100)
       b.BatchId,
       b.PackageName,
       b.BatchStart,
       b.BatchEnd,
       DATEDIFF(MINUTE, b.BatchStart, b.BatchEnd) AS DureeMinutes,
       b.[Status],
       b.LaunchedBy,
       b.ErrorMessage
  FROM etl.Batch AS b
 ORDER BY b.BatchId DESC;
GO

CREATE OR ALTER VIEW etl.vw_Suivi_Etapes
AS
SELECT TOP (1000)
       s.BatchId,
       s.StepId,
       s.StepName,
       s.StepStart,
       s.DurationSec,
       s.[Status],
       s.RowsRead,
       s.RowsInserted,
       s.RowsUpdated,
       s.RowsDeleted,
       s.RowsRejected,
       s.[Message]
  FROM etl.StepLog AS s
 ORDER BY s.StepId DESC;
GO

PRINT N'02 - CH_ADMIN : OK';
