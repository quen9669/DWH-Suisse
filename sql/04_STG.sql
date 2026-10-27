/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 04_STG.sql
   Base        : CH_STG
   Rôle        : Zone de PRÉPARATION (staging).
                 - convertit le texte brut en vrais types (dates, nombres, booléens)
                 - applique les règles de qualité (rejets, doublons, valeurs aberrantes)
                 - calcule les retards
                 Les tables stg.* sont vidées à chaque lot (zone de passage) ;
                 seules les tables de rejets sont conservées pour analyse.
   Ré-exécutable : OUI
   ============================================================================= */
USE CH_STG;
GO

/* ---------------------------------------------------------------------------
   Tables
   --------------------------------------------------------------------------- */
IF OBJECT_ID(N'stg.Istdaten', N'U') IS NULL
CREATE TABLE stg.Istdaten
(
    OperatingDate      DATE          NOT NULL,
    TripId             NVARCHAR(255) NOT NULL,
    OperatorId         NVARCHAR(255) NULL,
    OperatorAbbr       NVARCHAR(255) NULL,
    OperatorName       NVARCHAR(255) NULL,
    ProductCode        NVARCHAR(255) NULL,
    LineId             NVARCHAR(255) NULL,
    LineText           NVARCHAR(255) NULL,
    ServiceType        NVARCHAR(255) NULL,
    IsAdditionalTrip   BIT           NOT NULL,
    IsCancelled        BIT           NOT NULL,
    StopUic            INT           NOT NULL,
    StopName           NVARCHAR(255) NULL,
    Sloid              NVARCHAR(255) NULL,
    ArrivalPlanned     DATETIME2(0)  NULL,
    ArrivalActual      DATETIME2(0)  NULL,
    ArrivalStatus      NVARCHAR(20)  NOT NULL,
    DeparturePlanned   DATETIME2(0)  NULL,
    DepartureActual    DATETIME2(0)  NULL,
    DepartureStatus    NVARCHAR(20)  NOT NULL,
    IsPassThrough      BIT           NOT NULL,
    ArrivalDelaySec    INT           NULL,
    DepartureDelaySec  INT           NULL,
    IsDelayOutlier     BIT           NOT NULL,
    _SourceFile        NVARCHAR(260) NOT NULL,
    _BatchId           INT           NOT NULL
);
GO

IF OBJECT_ID(N'stg.Istdaten_Rejet', N'U') IS NULL
CREATE TABLE stg.Istdaten_Rejet
(
    RejetId            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Istdaten_Rejet PRIMARY KEY,
    RejectReason       NVARCHAR(100) NOT NULL,
    BETRIEBSTAG        NVARCHAR(255) NULL,
    FAHRT_BEZEICHNER   NVARCHAR(255) NULL,
    BPUIC              NVARCHAR(255) NULL,
    HALTESTELLEN_NAME  NVARCHAR(255) NULL,
    ANKUNFTSZEIT       NVARCHAR(255) NULL,
    ABFAHRTSZEIT       NVARCHAR(255) NULL,
    _SourceFile        NVARCHAR(260) NOT NULL,
    _BatchId           INT           NOT NULL,
    RejectDtm          DATETIME2(0)  NOT NULL CONSTRAINT DF_IstdatenRejet_Dtm DEFAULT (SYSDATETIME())
);
GO

IF OBJECT_ID(N'stg.ServicePoint', N'U') IS NULL
CREATE TABLE stg.ServicePoint
(
    Uic                INT           NOT NULL CONSTRAINT PK_stg_ServicePoint PRIMARY KEY,
    Sloid              NVARCHAR(255) NULL,
    StationName        NVARCHAR(255) NOT NULL,
    Abbreviation       NVARCHAR(255) NULL,
    CountryIso         NVARCHAR(10)  NULL,
    CantonName         NVARCHAR(255) NULL,
    CantonAbbr         NVARCHAR(10)  NULL,
    DistrictName       NVARCHAR(255) NULL,
    MunicipalityName   NVARCHAR(255) NULL,
    LocalityName       NVARCHAR(255) NULL,
    MeansOfTransport   NVARCHAR(255) NULL,
    IsStopPoint        BIT           NOT NULL,
    OwnerAbbr          NVARCHAR(255) NULL,
    OwnerName          NVARCHAR(255) NULL,
    Latitude           DECIMAL(9,6)  NULL,
    Longitude          DECIMAL(9,6)  NULL,
    Altitude           DECIMAL(7,1)  NULL,
    HashDiff           VARBINARY(32) NOT NULL,   -- empreinte pour détecter les changements (SCD2)
    _BatchId           INT           NOT NULL
);
GO

IF OBJECT_ID(N'stg.Meteo', N'U') IS NULL
CREATE TABLE stg.Meteo
(
    CantonAbbr         NVARCHAR(10)  NOT NULL,
    ObsDate            DATE          NOT NULL,
    ObsHour            TINYINT       NOT NULL,
    Temperature        DECIMAL(5,1)  NULL,   -- °C
    Precipitation      DECIMAL(6,2)  NULL,   -- mm
    Snowfall           DECIMAL(6,2)  NULL,   -- cm
    WindSpeed          DECIMAL(5,1)  NULL,   -- km/h
    _SourceFile        NVARCHAR(260) NOT NULL,
    _BatchId           INT           NOT NULL,
    CONSTRAINT PK_stg_Meteo PRIMARY KEY (CantonAbbr, ObsDate, ObsHour)
);
GO

/* ---------------------------------------------------------------------------
   stg.usp_Load_Istdaten
   Traite, fichier par fichier, les fichiers Istdaten reçus dans l'ODS mais
   pas encore intégrés à l'entrepôt (statut ODS_OK dans CH_ADMIN.etl.FileLog).
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE stg.usp_Load_Istdaten
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StepId INT, @File NVARCHAR(260),
            @Read BIGINT = 0, @Ins BIGINT = 0, @Rej BIGINT = 0, @n BIGINT;

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'stg.usp_Load_Istdaten', @StepId OUTPUT;

    BEGIN TRY
        TRUNCATE TABLE stg.Istdaten;

        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT [FileName] FROM CH_ADMIN.etl.FileLog
             WHERE SourceType = N'ISTDATEN' AND [Status] = N'ODS_OK'
             ORDER BY [FileName];
        OPEN cur;
        FETCH NEXT FROM cur INTO @File;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            /* 1) Conversion des types (TRY_CONVERT renvoie NULL au lieu de planter) */
            DROP TABLE IF EXISTS #src;

            SELECT
                o.BETRIEBSTAG, o.FAHRT_BEZEICHNER, o.BPUIC, o.HALTESTELLEN_NAME,
                o.ANKUNFTSZEIT, o.ABFAHRTSZEIT,
                TRY_CONVERT(DATE, o.BETRIEBSTAG, 104)                                AS OperatingDate,
                NULLIF(LTRIM(RTRIM(o.FAHRT_BEZEICHNER)), N'')                        AS TripId,
                NULLIF(o.BETREIBER_ID,   N'')                                        AS OperatorId,
                NULLIF(o.BETREIBER_ABK,  N'')                                        AS OperatorAbbr,
                NULLIF(o.BETREIBER_NAME, N'')                                        AS OperatorName,
                NULLIF(o.PRODUKT_ID,     N'')                                        AS ProductCode,
                NULLIF(o.LINIEN_ID,      N'')                                        AS LineId,
                NULLIF(o.LINIEN_TEXT,    N'')                                        AS LineText,
                NULLIF(o.VERKEHRSMITTEL_TEXT, N'')                                   AS ServiceType,
                CASE WHEN LOWER(o.ZUSATZFAHRT_TF) = N'true' THEN 1 ELSE 0 END        AS IsAdditionalTrip,
                CASE WHEN LOWER(o.FAELLT_AUS_TF)  = N'true' THEN 1 ELSE 0 END        AS IsCancelled,
                TRY_CONVERT(INT, o.BPUIC)                                            AS StopUic,
                NULLIF(o.SLOID, N'')                                                 AS Sloid,
                TRY_CONVERT(DATETIME2(0), NULLIF(o.ANKUNFTSZEIT, N''), 104)          AS ArrivalPlanned,
                TRY_CONVERT(DATETIME2(0), NULLIF(o.AN_PROGNOSE,  N''), 104)          AS ArrivalActual,
                UPPER(NULLIF(LTRIM(RTRIM(o.AN_PROGNOSE_STATUS)), N''))               AS ArrivalStatusRaw,
                TRY_CONVERT(DATETIME2(0), NULLIF(o.ABFAHRTSZEIT, N''), 104)          AS DeparturePlanned,
                TRY_CONVERT(DATETIME2(0), NULLIF(o.AB_PROGNOSE,  N''), 104)          AS DepartureActual,
                UPPER(NULLIF(LTRIM(RTRIM(o.AB_PROGNOSE_STATUS)), N''))               AS DepartureStatusRaw,
                CASE WHEN LOWER(o.DURCHFAHRT_TF) = N'true' THEN 1 ELSE 0 END         AS IsPassThrough
            INTO #src
            FROM CH_ODS.ods.Istdaten AS o
            WHERE o._SourceFile = @File;

            SET @n = @@ROWCOUNT;
            SET @Read += @n;

            /* 2) Règles de qualité : une ligne invalide part en table de rejets avec son motif */
            ;WITH q AS
            (
                SELECT s.*,
                       CASE
                           WHEN s.OperatingDate IS NULL                               THEN N'Jour d''exploitation invalide'
                           WHEN s.TripId IS NULL                                      THEN N'Identifiant de trajet manquant'
                           WHEN s.StopUic IS NULL                                     THEN N'N° d''arrêt (BPUIC) invalide'
                           WHEN s.ArrivalPlanned IS NULL AND s.DeparturePlanned IS NULL THEN N'Aucun horaire prévu'
                       END AS RejectReason,
                       ROW_NUMBER() OVER (PARTITION BY s.OperatingDate, s.TripId, s.StopUic,
                                                       s.ArrivalPlanned, s.DeparturePlanned
                                          ORDER BY (SELECT NULL)) AS rn
                  FROM #src AS s
            )
            INSERT INTO stg.Istdaten_Rejet
                   (RejectReason, BETRIEBSTAG, FAHRT_BEZEICHNER, BPUIC, HALTESTELLEN_NAME,
                    ANKUNFTSZEIT, ABFAHRTSZEIT, _SourceFile, _BatchId)
            SELECT COALESCE(q.RejectReason, N'Doublon'),
                   q.BETRIEBSTAG, q.FAHRT_BEZEICHNER, q.BPUIC, q.HALTESTELLEN_NAME,
                   q.ANKUNFTSZEIT, q.ABFAHRTSZEIT, @File, @BatchId
              FROM q
             WHERE q.RejectReason IS NOT NULL
                OR q.rn > 1;

            SET @Rej += @@ROWCOUNT;

            /* 3) Lignes valides -> stg.Istdaten, avec calcul des retards */
            ;WITH v AS
            (
                SELECT s.*,
                       ROW_NUMBER() OVER (PARTITION BY s.OperatingDate, s.TripId, s.StopUic,
                                                       s.ArrivalPlanned, s.DeparturePlanned
                                          ORDER BY (SELECT NULL)) AS rn,
                       DATEDIFF(SECOND, s.ArrivalPlanned,   s.ArrivalActual)   AS ArrDelay,
                       DATEDIFF(SECOND, s.DeparturePlanned, s.DepartureActual) AS DepDelay
                  FROM #src AS s
                 WHERE s.OperatingDate IS NOT NULL
                   AND s.TripId        IS NOT NULL
                   AND s.StopUic       IS NOT NULL
                   AND (s.ArrivalPlanned IS NOT NULL OR s.DeparturePlanned IS NOT NULL)
            )
            INSERT INTO stg.Istdaten
                   (OperatingDate, TripId, OperatorId, OperatorAbbr, OperatorName, ProductCode,
                    LineId, LineText, ServiceType, IsAdditionalTrip, IsCancelled, StopUic, StopName,
                    Sloid, ArrivalPlanned, ArrivalActual, ArrivalStatus, DeparturePlanned,
                    DepartureActual, DepartureStatus, IsPassThrough, ArrivalDelaySec,
                    DepartureDelaySec, IsDelayOutlier, _SourceFile, _BatchId)
            SELECT v.OperatingDate, v.TripId, v.OperatorId, v.OperatorAbbr, v.OperatorName, v.ProductCode,
                   v.LineId, v.LineText, v.ServiceType, v.IsAdditionalTrip, v.IsCancelled, v.StopUic,
                   v.HALTESTELLEN_NAME, v.Sloid,
                   v.ArrivalPlanned, v.ArrivalActual,
                   -- Statut vide = PROGNOSE (règle de la documentation officielle) ;
                   -- pas d'horaire prévu = SANS_OBJET (ex. arrivée au 1er arrêt d'un trajet)
                   CASE WHEN v.ArrivalPlanned IS NULL THEN N'SANS_OBJET'
                        ELSE COALESCE(v.ArrivalStatusRaw, N'PROGNOSE') END,
                   v.DeparturePlanned, v.DepartureActual,
                   CASE WHEN v.DeparturePlanned IS NULL THEN N'SANS_OBJET'
                        ELSE COALESCE(v.DepartureStatusRaw, N'PROGNOSE') END,
                   v.IsPassThrough,
                   v.ArrDelay, v.DepDelay,
                   -- Retard aberrant : plus de 30 min d'avance ou plus de 6 h de retard
                   CASE WHEN v.ArrDelay < -1800 OR v.ArrDelay > 21600
                          OR v.DepDelay < -1800 OR v.DepDelay > 21600 THEN 1 ELSE 0 END,
                   @File, @BatchId
              FROM v
             WHERE v.rn = 1;

            SET @Ins += @@ROWCOUNT;

            FETCH NEXT FROM cur INTO @File;
        END;

        CLOSE cur;
        DEALLOCATE cur;
        DROP TABLE IF EXISTS #src;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès',
             @RowsRead = @Read, @RowsInserted = @Ins, @RowsRejected = @Rej;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'cur') >= 0 BEGIN CLOSE cur; DEALLOCATE cur; END;
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------------
   stg.usp_Load_ServicePoint
   Type, nettoie et calcule l'empreinte (HashDiff) des points d'arrêt.
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE stg.usp_Load_ServicePoint
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StepId INT, @Read BIGINT, @Ins BIGINT;

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'stg.usp_Load_ServicePoint', @StepId OUTPUT;

    BEGIN TRY
        TRUNCATE TABLE stg.ServicePoint;

        SELECT @Read = COUNT_BIG(*) FROM CH_ODS.ods.ServicePoint;

        ;WITH s AS
        (
            SELECT
                TRY_CONVERT(INT, o.number)                                AS Uic,
                NULLIF(o.sloid, N'')                                      AS Sloid,
                COALESCE(NULLIF(o.designationOfficial, N''), N'(sans nom)') AS StationName,
                NULLIF(o.abbreviation, N'')                               AS Abbreviation,
                NULLIF(o.isoCountryCode, N'')                             AS CountryIso,
                NULLIF(o.cantonName, N'')                                 AS CantonName,
                NULLIF(o.cantonAbbreviation, N'')                         AS CantonAbbr,
                NULLIF(o.districtName, N'')                               AS DistrictName,
                NULLIF(o.municipalityName, N'')                           AS MunicipalityName,
                NULLIF(o.localityName, N'')                               AS LocalityName,
                NULLIF(o.meansOfTransport, N'')                           AS MeansOfTransport,
                CASE WHEN LOWER(o.stopPoint) = N'true' THEN 1 ELSE 0 END  AS IsStopPoint,
                NULLIF(o.businessOrganisationAbbreviationFr, N'')         AS OwnerAbbr,
                NULLIF(o.businessOrganisationDescriptionFr, N'')          AS OwnerName,
                TRY_CONVERT(DECIMAL(9,6), NULLIF(o.wgs84North, N''))      AS Latitude,
                TRY_CONVERT(DECIMAL(9,6), NULLIF(o.wgs84East,  N''))      AS Longitude,
                TRY_CONVERT(DECIMAL(7,1), NULLIF(o.height,     N''))      AS Altitude,
                ROW_NUMBER() OVER (PARTITION BY o.number ORDER BY o.validFrom DESC) AS rn
            FROM CH_ODS.ods.ServicePoint AS o
        )
        INSERT INTO stg.ServicePoint
               (Uic, Sloid, StationName, Abbreviation, CountryIso, CantonName, CantonAbbr,
                DistrictName, MunicipalityName, LocalityName, MeansOfTransport, IsStopPoint,
                OwnerAbbr, OwnerName, Latitude, Longitude, Altitude, HashDiff, _BatchId)
        SELECT s.Uic, s.Sloid, s.StationName, s.Abbreviation, s.CountryIso, s.CantonName, s.CantonAbbr,
               s.DistrictName, s.MunicipalityName, s.LocalityName, s.MeansOfTransport, s.IsStopPoint,
               s.OwnerAbbr, s.OwnerName, s.Latitude, s.Longitude, s.Altitude,
               -- Empreinte des attributs suivis en historique : si elle change, nouvelle version
               HASHBYTES('SHA2_256', CONCAT_WS(N'|', s.StationName, s.Abbreviation, s.CountryIso,
                         s.CantonAbbr, s.DistrictName, s.MunicipalityName, s.LocalityName,
                         s.MeansOfTransport, s.IsStopPoint, s.OwnerAbbr, s.Latitude, s.Longitude)),
               @BatchId
          FROM s
         WHERE s.Uic IS NOT NULL
           AND s.rn = 1;

        SET @Ins = @@ROWCOUNT;

        DECLARE @Rej BIGINT = @Read - @Ins;   -- n° invalide ou doublon
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès',
             @RowsRead = @Read, @RowsInserted = @Ins, @RowsRejected = @Rej;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------------
   stg.usp_Load_Meteo
   "Déplie" les JSON Open-Meteo : chaque réponse contient des tableaux
   parallèles (heures, températures, pluie...). On les relie par leur position.
   Nom de fichier attendu : meteo_<CANTON>_<AAAA-MM-JJ>.json
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE stg.usp_Load_Meteo
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StepId INT, @Read BIGINT, @Ins BIGINT;

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'stg.usp_Load_Meteo', @StepId OUTPUT;

    BEGIN TRY
        TRUNCATE TABLE stg.Meteo;

        DROP TABLE IF EXISTS #m;

        SELECT
            SUBSTRING(o._SourceFile, 7, 2)                           AS CantonAbbr,
            TRY_CONVERT(DATETIME2(0), CONCAT(t.[value], N':00'), 126) AS ObsDtm,  -- "2026-10-25T14:00" + ":00"
            -- même position [key] dans chaque tableau = même heure
            TRY_CONVERT(DECIMAL(5,1), JSON_VALUE(o.JsonContent, CONCAT(N'$.hourly.temperature_2m[', t.[key], N']'))) AS Temperature,
            TRY_CONVERT(DECIMAL(6,2), JSON_VALUE(o.JsonContent, CONCAT(N'$.hourly.precipitation[',  t.[key], N']'))) AS Precipitation,
            TRY_CONVERT(DECIMAL(6,2), JSON_VALUE(o.JsonContent, CONCAT(N'$.hourly.snowfall[',       t.[key], N']'))) AS Snowfall,
            TRY_CONVERT(DECIMAL(5,1), JSON_VALUE(o.JsonContent, CONCAT(N'$.hourly.wind_speed_10m[', t.[key], N']'))) AS WindSpeed,
            o._SourceFile
        INTO #m
        FROM CH_ODS.ods.MeteoJson AS o
        JOIN CH_ADMIN.etl.FileLog AS f
          ON f.SourceType = N'METEO' AND f.[FileName] = o._SourceFile AND f.[Status] = N'ODS_OK'
        CROSS APPLY OPENJSON(o.JsonContent, N'$.hourly.time') AS t;

        SET @Read = @@ROWCOUNT;

        /* Regroupement par heure : lors du passage à l'heure d'hiver, la même
           heure locale apparaît deux fois -> moyenne / somme. */
        INSERT INTO stg.Meteo
               (CantonAbbr, ObsDate, ObsHour, Temperature, Precipitation, Snowfall, WindSpeed, _SourceFile, _BatchId)
        SELECT m.CantonAbbr,
               CAST(m.ObsDtm AS DATE),
               DATEPART(HOUR, m.ObsDtm),
               AVG(m.Temperature),
               SUM(m.Precipitation),
               SUM(m.Snowfall),
               AVG(m.WindSpeed),
               MIN(m._SourceFile),
               @BatchId
          FROM #m AS m
         WHERE m.ObsDtm IS NOT NULL
         GROUP BY m.CantonAbbr, CAST(m.ObsDtm AS DATE), DATEPART(HOUR, m.ObsDtm);

        SET @Ins = @@ROWCOUNT;

        DROP TABLE IF EXISTS #m;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès', @RowsRead = @Read, @RowsInserted = @Ins;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

PRINT N'04 - CH_STG : OK';
