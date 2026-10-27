/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 03_ODS.sql
   Base        : CH_ODS
   Rôle        : Zone BRUTE (Operational Data Store).
                 Règle d'or : on stocke les données EXACTEMENT comme reçues
                 (tout en texte, noms de colonnes d'origine) + 3 colonnes d'audit :
                   _BatchId    : n° du lot qui a chargé la ligne
                   _SourceFile : nom du fichier d'origine
                   _LoadDtm    : date/heure de chargement
                 Aucune transformation ici : si une règle métier change, on peut
                 toujours rejouer depuis l'ODS sans re-télécharger.
   Ré-exécutable : OUI
   ============================================================================= */
USE CH_ODS;
GO

/* ---------------------------------------------------------------------------
   ods.Istdaten : passages réels des transports publics (source opentransportdata.swiss)
   Un fichier par jour, ~2 à 3 millions de lignes, séparateur ";".
   Index COLUMNSTORE : compresse ~10x les colonnes texte répétitives.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'ods.Istdaten', N'U') IS NULL
CREATE TABLE ods.Istdaten
(
    BETRIEBSTAG          NVARCHAR(255) NULL,  -- jour d'exploitation (jj.mm.aaaa)
    FAHRT_BEZEICHNER     NVARCHAR(255) NULL,  -- identifiant du trajet
    BETREIBER_ID         NVARCHAR(255) NULL,  -- identifiant de l'opérateur
    BETREIBER_ABK        NVARCHAR(255) NULL,  -- abréviation de l'opérateur (ex. SBB)
    BETREIBER_NAME       NVARCHAR(255) NULL,  -- nom de l'opérateur
    PRODUKT_ID           NVARCHAR(255) NULL,  -- mode de transport (Zug, Bus, Tram...)
    LINIEN_ID            NVARCHAR(255) NULL,  -- n° de ligne / de train
    LINIEN_TEXT          NVARCHAR(255) NULL,  -- libellé de ligne (ex. IC1, 31)
    UMLAUF_ID            NVARCHAR(255) NULL,  -- identifiant de roulement
    VERKEHRSMITTEL_TEXT  NVARCHAR(255) NULL,  -- type de service (IC, RE, S, B...)
    ZUSATZFAHRT_TF       NVARCHAR(255) NULL,  -- trajet supplémentaire (true/false)
    FAELLT_AUS_TF        NVARCHAR(255) NULL,  -- trajet supprimé (true/false)
    BPUIC                NVARCHAR(255) NULL,  -- n° UIC de l'arrêt
    HALTESTELLEN_NAME    NVARCHAR(255) NULL,  -- nom de l'arrêt
    ANKUNFTSZEIT         NVARCHAR(255) NULL,  -- arrivée prévue
    AN_PROGNOSE          NVARCHAR(255) NULL,  -- arrivée réelle / prévue
    AN_PROGNOSE_STATUS   NVARCHAR(255) NULL,  -- REAL / GESCHAETZT / PROGNOSE / UNBEKANNT
    ABFAHRTSZEIT         NVARCHAR(255) NULL,  -- départ prévu
    AB_PROGNOSE          NVARCHAR(255) NULL,  -- départ réel / prévu
    AB_PROGNOSE_STATUS   NVARCHAR(255) NULL,
    DURCHFAHRT_TF        NVARCHAR(255) NULL,  -- passage sans arrêt (true/false)
    SLOID                NVARCHAR(255) NULL,  -- identifiant suisse de l'arrêt
    _BatchId             INT           NOT NULL,
    _SourceFile          NVARCHAR(260) NOT NULL,
    _LoadDtm             DATETIME2(0)  NOT NULL CONSTRAINT DF_OdsIstdaten_LoadDtm DEFAULT (SYSDATETIME())
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CCI_ods_Istdaten')
    CREATE CLUSTERED COLUMNSTORE INDEX CCI_ods_Istdaten ON ods.Istdaten;
GO

/* ---------------------------------------------------------------------------
   ods.ServicePoint : référentiel des points d'arrêt (gares, arrêts de bus...)
   Source : "Service Points (Actual Date)" - 55 colonnes, séparateur ";".
   Photo complète : vidée et rechargée à chaque lot.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'ods.ServicePoint', N'U') IS NULL
CREATE TABLE ods.ServicePoint
(
    numberShort                          NVARCHAR(255) NULL,
    uicCountryCode                       NVARCHAR(255) NULL,
    sloid                                NVARCHAR(255) NULL,
    number                               NVARCHAR(255) NULL,  -- = BPUIC des Istdaten
    checkDigit                           NVARCHAR(255) NULL,
    validFrom                            NVARCHAR(255) NULL,
    validTo                              NVARCHAR(255) NULL,
    designationOfficial                  NVARCHAR(255) NULL,
    designationLong                      NVARCHAR(255) NULL,
    abbreviation                         NVARCHAR(255) NULL,
    operatingPoint                       NVARCHAR(255) NULL,
    operatingPointWithTimetable          NVARCHAR(255) NULL,
    stopPoint                            NVARCHAR(255) NULL,
    stopPointType                        NVARCHAR(255) NULL,
    freightServicePoint                  NVARCHAR(255) NULL,
    trafficPoint                         NVARCHAR(255) NULL,
    borderPoint                          NVARCHAR(255) NULL,
    hasGeolocation                       NVARCHAR(255) NULL,
    isoCountryCode                       NVARCHAR(255) NULL,
    cantonName                           NVARCHAR(255) NULL,
    cantonFsoNumber                      NVARCHAR(255) NULL,
    cantonAbbreviation                   NVARCHAR(255) NULL,
    districtName                         NVARCHAR(255) NULL,
    districtFsoNumber                    NVARCHAR(255) NULL,
    municipalityName                     NVARCHAR(255) NULL,
    fsoNumber                            NVARCHAR(255) NULL,
    localityName                         NVARCHAR(255) NULL,
    operatingPointType                   NVARCHAR(255) NULL,
    operatingPointTechnicalTimetableType NVARCHAR(255) NULL,
    meansOfTransport                     NVARCHAR(255) NULL,
    categories                           NVARCHAR(255) NULL,
    operatingPointTrafficPointType       NVARCHAR(255) NULL,
    operatingPointRouteNetwork           NVARCHAR(255) NULL,
    operatingPointKilometer              NVARCHAR(255) NULL,
    operatingPointKilometerMasterNumber  NVARCHAR(255) NULL,
    sortCodeOfDestinationStation         NVARCHAR(255) NULL,
    businessOrganisation                 NVARCHAR(255) NULL,
    businessOrganisationNumber           NVARCHAR(255) NULL,
    businessOrganisationAbbreviationDe   NVARCHAR(255) NULL,
    businessOrganisationAbbreviationFr   NVARCHAR(255) NULL,
    businessOrganisationAbbreviationIt   NVARCHAR(255) NULL,
    businessOrganisationAbbreviationEn   NVARCHAR(255) NULL,
    businessOrganisationDescriptionDe    NVARCHAR(255) NULL,
    businessOrganisationDescriptionFr    NVARCHAR(255) NULL,
    businessOrganisationDescriptionIt    NVARCHAR(255) NULL,
    businessOrganisationDescriptionEn    NVARCHAR(255) NULL,
    fotComment                           NVARCHAR(1000) NULL,
    lv95East                             NVARCHAR(255) NULL,
    lv95North                            NVARCHAR(255) NULL,
    wgs84East                            NVARCHAR(255) NULL,
    wgs84North                           NVARCHAR(255) NULL,
    height                               NVARCHAR(255) NULL,
    creationDate                         NVARCHAR(255) NULL,
    editionDate                          NVARCHAR(255) NULL,
    [status]                             NVARCHAR(255) NULL,
    _BatchId                             INT           NOT NULL,
    _SourceFile                          NVARCHAR(260) NOT NULL,
    _LoadDtm                             DATETIME2(0)  NOT NULL CONSTRAINT DF_OdsServicePoint_LoadDtm DEFAULT (SYSDATETIME())
);
GO

/* ---------------------------------------------------------------------------
   ods.MeteoJson : réponses JSON brutes de l'API Open-Meteo
   Un fichier = un canton x un jour. Le JSON est stocké tel quel ;
   il sera "déplié" dans la zone STG avec OPENJSON.
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'ods.MeteoJson', N'U') IS NULL
CREATE TABLE ods.MeteoJson
(
    MeteoJsonId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MeteoJson PRIMARY KEY,
    JsonContent   NVARCHAR(MAX)     NOT NULL,
    _BatchId      INT               NOT NULL,
    _SourceFile   NVARCHAR(260)     NOT NULL,
    _LoadDtm      DATETIME2(0)      NOT NULL CONSTRAINT DF_OdsMeteo_LoadDtm DEFAULT (SYSDATETIME())
);
GO

/* ---------------------------------------------------------------------------
   Procédures
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ods.usp_Istdaten_PrepareFile
    @SourceFile NVARCHAR(260)
AS
/* Avant de charger un fichier : supprime ses lignes éventuellement déjà
   présentes (cas d'une reprise après incident). Le chargement est ainsi
   "idempotent" : le relancer 2 fois donne le même résultat. */
BEGIN
    SET NOCOUNT ON;
    DELETE FROM ods.Istdaten WHERE _SourceFile = @SourceFile;
    SELECT @@ROWCOUNT AS RowsDeleted;
END;
GO

CREATE OR ALTER PROCEDURE ods.usp_Load_MeteoJson
    @FilePath NVARCHAR(400),
    @BatchId  INT
AS
/* Charge un fichier JSON (encodé en UTF-16 par le script PowerShell) dans
   ods.MeteoJson, puis l'enregistre dans le journal des fichiers.
   ATTENTION : c'est le service SQL Server qui lit le fichier ; il doit avoir
   le droit de lecture sur le dossier (voir docs/08_Exploitation.md). */
BEGIN
    SET NOCOUNT ON;

    DECLARE @FileName NVARCHAR(260) = RIGHT(@FilePath, CHARINDEX(N'\', REVERSE(@FilePath)) - 1);
    DECLARE @Json     NVARCHAR(MAX);
    DECLARE @Sql      NVARCHAR(MAX) =
        N'SELECT @j = BulkColumn FROM OPENROWSET(BULK N''' + REPLACE(@FilePath, N'''', N'''''') + N''', SINGLE_NCLOB) AS f;';

    EXEC sys.sp_executesql @Sql, N'@j NVARCHAR(MAX) OUTPUT', @j = @Json OUTPUT;

    -- Retire un éventuel BOM (marque d'encodage) en tête de fichier
    IF LEFT(@Json, 1) = NCHAR(65279) SET @Json = STUFF(@Json, 1, 1, N'');

    IF ISJSON(@Json) = 0
        THROW 50001, N'Le fichier météo ne contient pas un JSON valide.', 1;

    DELETE FROM ods.MeteoJson WHERE _SourceFile = @FileName;

    INSERT INTO ods.MeteoJson (JsonContent, _BatchId, _SourceFile)
    VALUES (@Json, @BatchId, @FileName);

    EXEC CH_ADMIN.etl.usp_File_Register
         @SourceType = N'METEO', @FileName = @FileName, @BatchId = @BatchId, @RowsOds = 1;
END;
GO

CREATE OR ALTER PROCEDURE ods.usp_Purge
    @BatchId       INT,
    @RetentionDays INT = 30
AS
/* Purge de l'ODS : supprime les données brutes déjà intégrées à l'entrepôt
   (statut DWH_OK) et chargées il y a plus de @RetentionDays jours. */
BEGIN
    SET NOCOUNT ON;

    DECLARE @StepId INT, @Del BIGINT = 0;
    DECLARE @Limit DATETIME2(0) = DATEADD(DAY, -@RetentionDays, SYSDATETIME());

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'ods.usp_Purge', @StepId OUTPUT;

    BEGIN TRY
        DELETE o
          FROM ods.Istdaten AS o
         WHERE o._LoadDtm < @Limit
           AND EXISTS (SELECT 1 FROM CH_ADMIN.etl.FileLog AS f
                        WHERE f.SourceType = N'ISTDATEN' AND f.[FileName] = o._SourceFile
                          AND f.[Status] = N'DWH_OK');
        SET @Del += @@ROWCOUNT;

        DELETE o
          FROM ods.MeteoJson AS o
         WHERE o._LoadDtm < @Limit
           AND EXISTS (SELECT 1 FROM CH_ADMIN.etl.FileLog AS f
                        WHERE f.SourceType = N'METEO' AND f.[FileName] = o._SourceFile
                          AND f.[Status] = N'DWH_OK');
        SET @Del += @@ROWCOUNT;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès', @RowsDeleted = @Del;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

PRINT N'03 - CH_ODS : OK';
