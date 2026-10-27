/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 07_DWH_Procedures.sql
   Base        : CH_DWH
   Rôle        : Procédures de chargement STG -> DWH, appelées par SSIS :
                   40_DWH_Dimensions.dtsx : Operator, TransportMode, Line, Station, Station déduites
                   41_DWH_Faits.dtsx      : StopEvent, WeatherHourly
                 Chaque procédure journalise son exécution dans CH_ADMIN.etl.StepLog.
   Ré-exécutable : OUI
   ============================================================================= */
USE CH_DWH;
GO

/* ---------------------------------------------------------------------------
   dim.Operator - SCD type 1 (on écrase les changements de nom)
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimOperator
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StepId INT, @Ins BIGINT = 0, @Upd BIGINT = 0;
    DECLARE @Out TABLE (Act NVARCHAR(10));

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'etl.usp_Load_DimOperator', @StepId OUTPUT;
    BEGIN TRY
        MERGE dim.Operator AS t
        USING (
            SELECT OperatorId,
                   COALESCE(MAX(OperatorAbbr), N'?')  AS OperatorAbbr,
                   COALESCE(MAX(OperatorName), N'?')  AS OperatorName
              FROM CH_STG.stg.Istdaten
             WHERE OperatorId IS NOT NULL
             GROUP BY OperatorId
        ) AS s
        ON t.OperatorId = s.OperatorId
        WHEN MATCHED AND (t.OperatorAbbr <> s.OperatorAbbr OR t.OperatorName <> s.OperatorName) THEN
            UPDATE SET OperatorAbbr = s.OperatorAbbr, OperatorName = s.OperatorName, UpdateBatchId = @BatchId
        WHEN NOT MATCHED THEN
            INSERT (OperatorId, OperatorAbbr, OperatorName, InsertBatchId)
            VALUES (s.OperatorId, s.OperatorAbbr, s.OperatorName, @BatchId)
        OUTPUT $action INTO @Out;

        SELECT @Ins = SUM(CASE WHEN Act = N'INSERT' THEN 1 ELSE 0 END),
               @Upd = SUM(CASE WHEN Act = N'UPDATE' THEN 1 ELSE 0 END)
          FROM @Out;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès', @RowsInserted = @Ins, @RowsUpdated = @Upd;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------------
   dim.TransportMode - ajoute les codes jamais vus (libellé = code)
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimTransportMode
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StepId INT, @Ins BIGINT;

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'etl.usp_Load_DimTransportMode', @StepId OUTPUT;
    BEGIN TRY
        INSERT INTO dim.TransportMode (ProductCode, ModeLabel, ModeCategory, InsertBatchId)
        SELECT DISTINCT s.ProductCode, LEFT(s.ProductCode, 50), N'À classer', @BatchId
          FROM CH_STG.stg.Istdaten AS s
         WHERE s.ProductCode IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dim.TransportMode AS t WHERE t.ProductCode = s.ProductCode);
        SET @Ins = @@ROWCOUNT;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId,
             CASE WHEN @Ins > 0 THEN N'Avertissement' ELSE N'Succès' END,
             @RowsInserted = @Ins,
             @Message = CASE WHEN @Ins > 0 THEN N'Nouveaux modes de transport à traduire dans 06_DWH_Referentiels.sql' END;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------------
   dim.Line - SCD type 1. Clé métier = opérateur + mode + code de ligne.
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimLine
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StepId INT, @Ins BIGINT = 0, @Upd BIGINT = 0;
    DECLARE @Out TABLE (Act NVARCHAR(10));

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'etl.usp_Load_DimLine', @StepId OUTPUT;
    BEGIN TRY
        MERGE dim.Line AS t
        USING (
            SELECT COALESCE(s.OperatorId, N'?')                       AS OperatorId,
                   COALESCE(s.ProductCode, N'?')                      AS ProductCode,
                   COALESCE(s.LineText, s.LineId, N'?')               AS LineCode,
                   MAX(s.ServiceType)                                 AS ServiceType,
                   CONCAT(COALESCE(MAX(s.OperatorAbbr), N'?'), N' - ',
                          COALESCE(s.LineText, s.LineId, N'?'))       AS LineLabel
              FROM CH_STG.stg.Istdaten AS s
             GROUP BY COALESCE(s.OperatorId, N'?'), COALESCE(s.ProductCode, N'?'),
                      COALESCE(s.LineText, s.LineId, N'?')
        ) AS s
        ON  t.OperatorId  = s.OperatorId
        AND t.ProductCode = s.ProductCode
        AND t.LineCode    = s.LineCode
        WHEN MATCHED AND (ISNULL(t.ServiceType, N'') <> ISNULL(s.ServiceType, N'') OR t.LineLabel <> s.LineLabel) THEN
            UPDATE SET ServiceType = s.ServiceType, LineLabel = s.LineLabel, UpdateBatchId = @BatchId
        WHEN NOT MATCHED THEN
            INSERT (OperatorId, ProductCode, LineCode, ServiceType, LineLabel, InsertBatchId)
            VALUES (s.OperatorId, s.ProductCode, s.LineCode, s.ServiceType, s.LineLabel, @BatchId)
        OUTPUT $action INTO @Out;

        SELECT @Ins = SUM(CASE WHEN Act = N'INSERT' THEN 1 ELSE 0 END),
               @Upd = SUM(CASE WHEN Act = N'UPDATE' THEN 1 ELSE 0 END)
          FROM @Out;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès', @RowsInserted = @Ins, @RowsUpdated = @Upd;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------------
   dim.Station - SCD type 2 (historisation)
     1) arrêts "déduits" désormais présents dans le référentiel -> complétés sur place
     2) arrêts dont un attribut suivi a changé -> ancienne version fermée + nouvelle version
        (si la version courante date d'aujourd'hui, simple mise à jour sur place)
     3) nouveaux arrêts -> insérés, valides depuis 1900-01-01
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimStation
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StepId INT, @Ins BIGINT = 0, @Upd BIGINT = 0;
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'etl.usp_Load_DimStation', @StepId OUTPUT;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM CH_STG.stg.ServicePoint)
            THROW 50010, N'stg.ServicePoint est vide : chargement des arrêts annulé (sécurité).', 1;

        BEGIN TRANSACTION;

        /* 1) Membres déduits -> complétés (type 1) */
        UPDATE d
           SET Sloid = s.Sloid, StationName = s.StationName, Abbreviation = s.Abbreviation,
               CountryIso = s.CountryIso, CantonAbbr = s.CantonAbbr, CantonName = s.CantonName,
               DistrictName = s.DistrictName, MunicipalityName = s.MunicipalityName,
               LocalityName = s.LocalityName, MeansOfTransport = s.MeansOfTransport,
               IsStopPoint = s.IsStopPoint, OwnerAbbr = s.OwnerAbbr, OwnerName = s.OwnerName,
               Latitude = s.Latitude, Longitude = s.Longitude, Altitude = s.Altitude,
               HashDiff = s.HashDiff, IsInferred = 0, UpdateBatchId = @BatchId
          FROM dim.Station AS d
          JOIN CH_STG.stg.ServicePoint AS s ON s.Uic = d.Uic
         WHERE d.IsInferred = 1 AND d.IsCurrent = 1;
        SET @Upd += @@ROWCOUNT;

        /* 2a) Changement le jour même de la création de la version -> mise à jour sur place */
        UPDATE d
           SET Sloid = s.Sloid, StationName = s.StationName, Abbreviation = s.Abbreviation,
               CountryIso = s.CountryIso, CantonAbbr = s.CantonAbbr, CantonName = s.CantonName,
               DistrictName = s.DistrictName, MunicipalityName = s.MunicipalityName,
               LocalityName = s.LocalityName, MeansOfTransport = s.MeansOfTransport,
               IsStopPoint = s.IsStopPoint, OwnerAbbr = s.OwnerAbbr, OwnerName = s.OwnerName,
               Latitude = s.Latitude, Longitude = s.Longitude, Altitude = s.Altitude,
               HashDiff = s.HashDiff, UpdateBatchId = @BatchId
          FROM dim.Station AS d
          JOIN CH_STG.stg.ServicePoint AS s ON s.Uic = d.Uic
         WHERE d.IsCurrent = 1 AND d.IsInferred = 0
           AND d.HashDiff <> s.HashDiff
           AND d.ValidFrom = @Today;
        SET @Upd += @@ROWCOUNT;

        /* 2b) Changement -> on ferme l'ancienne version... */
        DECLARE @Changed TABLE (Uic INT PRIMARY KEY);

        UPDATE d
           SET ValidTo = @Today, IsCurrent = 0, UpdateBatchId = @BatchId
        OUTPUT inserted.Uic INTO @Changed (Uic)
          FROM dim.Station AS d
          JOIN CH_STG.stg.ServicePoint AS s ON s.Uic = d.Uic
         WHERE d.IsCurrent = 1 AND d.IsInferred = 0
           AND d.HashDiff <> s.HashDiff
           AND d.ValidFrom < @Today;
        SET @Upd += @@ROWCOUNT;

        /* ...et on ouvre la nouvelle (2b) + nouveaux arrêts (3) */
        INSERT INTO dim.Station
               (Uic, Sloid, StationName, Abbreviation, CountryIso, CantonAbbr, CantonName,
                DistrictName, MunicipalityName, LocalityName, MeansOfTransport, IsStopPoint,
                OwnerAbbr, OwnerName, Latitude, Longitude, Altitude, HashDiff, IsInferred,
                ValidFrom, ValidTo, IsCurrent, InsertBatchId)
        SELECT s.Uic, s.Sloid, s.StationName, s.Abbreviation, s.CountryIso, s.CantonAbbr, s.CantonName,
               s.DistrictName, s.MunicipalityName, s.LocalityName, s.MeansOfTransport, s.IsStopPoint,
               s.OwnerAbbr, s.OwnerName, s.Latitude, s.Longitude, s.Altitude, s.HashDiff, 0,
               CASE WHEN c.Uic IS NOT NULL THEN @Today ELSE '1900-01-01' END,
               '9999-12-31', 1, @BatchId
          FROM CH_STG.stg.ServicePoint AS s
          LEFT JOIN @Changed AS c ON c.Uic = s.Uic
         WHERE c.Uic IS NOT NULL
            OR NOT EXISTS (SELECT 1 FROM dim.Station AS d WHERE d.Uic = s.Uic);
        SET @Ins = @@ROWCOUNT;

        COMMIT TRANSACTION;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès', @RowsInserted = @Ins, @RowsUpdated = @Upd;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------------
   dim.Station - membres déduits ("inferred members")
   Arrêts présents dans les passages mais absents du référentiel (souvent des
   arrêts étrangers). On les crée avec le nom lu dans les passages pour ne
   perdre aucun fait ; ils seront complétés si le référentiel les fournit.
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimStation_Inferred
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StepId INT, @Ins BIGINT;

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'etl.usp_Load_DimStation_Inferred', @StepId OUTPUT;
    BEGIN TRY
        INSERT INTO dim.Station
               (Uic, Sloid, StationName, CantonAbbr, IsInferred, ValidFrom, ValidTo, IsCurrent, InsertBatchId)
        SELECT i.StopUic,
               MAX(i.Sloid),
               COALESCE(MAX(i.StopName), N'(sans nom)'),
               N'??',
               1, '1900-01-01', '9999-12-31', 1, @BatchId
          FROM CH_STG.stg.Istdaten AS i
         WHERE NOT EXISTS (SELECT 1 FROM dim.Station AS d WHERE d.Uic = i.StopUic)
         GROUP BY i.StopUic;
        SET @Ins = @@ROWCOUNT;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès', @RowsInserted = @Ins;
    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------------
   fact.StopEvent - chargement "supprimer puis insérer" par jour d'exploitation
   (idempotent : relancer le même jour remplace les données au lieu de les doubler)
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_FactStopEvent
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StepId INT, @Del BIGINT = 0, @Ins BIGINT = 0, @Read BIGINT;

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'etl.usp_Load_FactStopEvent', @StepId OUTPUT;
    BEGIN TRY
        SELECT @Read = COUNT_BIG(*) FROM CH_STG.stg.Istdaten;

        BEGIN TRANSACTION;

        DELETE f
          FROM fact.StopEvent AS f
         WHERE f.DateKey IN (SELECT DISTINCT YEAR(OperatingDate) * 10000 + MONTH(OperatingDate) * 100 + DAY(OperatingDate)
                               FROM CH_STG.stg.Istdaten);
        SET @Del = @@ROWCOUNT;

        INSERT INTO fact.StopEvent WITH (TABLOCK)
               (DateKey, TimeKey, StationKey, CantonKey, OperatorKey, LineKey, TransportModeKey,
                ArrivalStatusKey, DepartureStatusKey, TripId, ArrivalPlanned, ArrivalActual,
                DeparturePlanned, DepartureActual, ArrivalDelaySec, DepartureDelaySec,
                ReferenceDelaySec, IsAdditionalTrip, IsPassThrough, IsDelayOutlier,
                StopCount, CancelledCount, MeasuredCount, PunctualCount, _BatchId)
        SELECT YEAR(i.OperatingDate) * 10000 + MONTH(i.OperatingDate) * 100 + DAY(i.OperatingDate),
               COALESCE(DATEPART(HOUR,   COALESCE(i.ArrivalPlanned, i.DeparturePlanned)) * 100
                      + DATEPART(MINUTE, COALESCE(i.ArrivalPlanned, i.DeparturePlanned)), -1),
               COALESCE(st.StationKey, -1),
               COALESCE(ca.CantonKey, -1),
               COALESCE(op.OperatorKey, -1),
               COALESCE(li.LineKey, -1),
               COALESCE(tm.TransportModeKey, -1),
               COALESCE(sa.StatusKey, -1),
               COALESCE(sd.StatusKey, -1),
               i.TripId, i.ArrivalPlanned, i.ArrivalActual, i.DeparturePlanned, i.DepartureActual,
               i.ArrivalDelaySec, i.DepartureDelaySec,
               r.RefDelay,
               i.IsAdditionalTrip, i.IsPassThrough, i.IsDelayOutlier,
               1,
               CASE WHEN i.IsCancelled = 1 THEN 1 ELSE 0 END,
               CASE WHEN r.RefDelay IS NOT NULL THEN 1 ELSE 0 END,
               CASE WHEN r.RefDelay IS NOT NULL AND r.RefDelay < 180 THEN 1 ELSE 0 END,
               @BatchId
          FROM CH_STG.stg.Istdaten AS i
          LEFT JOIN dim.Station AS st
                 ON st.Uic = i.StopUic
                AND i.OperatingDate >= st.ValidFrom
                AND i.OperatingDate <  st.ValidTo
          LEFT JOIN dim.Canton        AS ca ON ca.CantonAbbr = st.CantonAbbr
          LEFT JOIN dim.Operator      AS op ON op.OperatorId = i.OperatorId
          LEFT JOIN dim.Line          AS li ON li.OperatorId  = COALESCE(i.OperatorId, N'?')
                                           AND li.ProductCode = COALESCE(i.ProductCode, N'?')
                                           AND li.LineCode    = COALESCE(i.LineText, i.LineId, N'?')
          LEFT JOIN dim.TransportMode AS tm ON tm.ProductCode = i.ProductCode
          LEFT JOIN dim.MeasureStatus AS sa ON sa.StatusCode  = i.ArrivalStatus
          LEFT JOIN dim.MeasureStatus AS sd ON sd.StatusCode  = i.DepartureStatus
         CROSS APPLY
         (
            /* Retard de référence (règle de ponctualité CFF : arrivée < 3 min) :
               retard à l'arrivée s'il est mesuré, sinon au départ ; jamais pour
               un passage supprimé ou une valeur aberrante. */
            SELECT CASE
                       WHEN i.IsCancelled = 1 OR i.IsDelayOutlier = 1 THEN NULL
                       WHEN i.ArrivalStatus   IN (N'REAL', N'GESCHAETZT') THEN i.ArrivalDelaySec
                       WHEN i.DepartureStatus IN (N'REAL', N'GESCHAETZT') THEN i.DepartureDelaySec
                   END AS RefDelay
         ) AS r;
        SET @Ins = @@ROWCOUNT;

        COMMIT TRANSACTION;

        EXEC CH_ADMIN.etl.usp_File_SetDwhLoaded @SourceType = N'ISTDATEN', @BatchId = @BatchId;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès',
             @RowsRead = @Read, @RowsInserted = @Ins, @RowsDeleted = @Del;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

/* ---------------------------------------------------------------------------
   fact.WeatherHourly - "supprimer puis insérer" par jour et canton
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_FactWeatherHourly
    @BatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @StepId INT, @Del BIGINT = 0, @Ins BIGINT = 0;

    EXEC CH_ADMIN.etl.usp_Step_Start @BatchId, N'etl.usp_Load_FactWeatherHourly', @StepId OUTPUT;
    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE f
          FROM fact.WeatherHourly AS f
          JOIN dim.Canton AS c ON c.CantonKey = f.CantonKey
         WHERE EXISTS (SELECT 1 FROM CH_STG.stg.Meteo AS m
                        WHERE m.CantonAbbr = c.CantonAbbr
                          AND YEAR(m.ObsDate) * 10000 + MONTH(m.ObsDate) * 100 + DAY(m.ObsDate) = f.DateKey);
        SET @Del = @@ROWCOUNT;

        INSERT INTO fact.WeatherHourly
               (DateKey, TimeKey, CantonKey, Temperature, Precipitation, Snowfall, WindSpeed, _BatchId)
        SELECT YEAR(m.ObsDate) * 10000 + MONTH(m.ObsDate) * 100 + DAY(m.ObsDate),
               m.ObsHour * 100,
               c.CantonKey,
               m.Temperature, m.Precipitation, m.Snowfall, m.WindSpeed,
               @BatchId
          FROM CH_STG.stg.Meteo AS m
          JOIN dim.Canton AS c ON c.CantonAbbr = m.CantonAbbr;
        SET @Ins = @@ROWCOUNT;

        COMMIT TRANSACTION;

        EXEC CH_ADMIN.etl.usp_File_SetDwhLoaded @SourceType = N'METEO', @BatchId = @BatchId;

        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Succès', @RowsInserted = @Ins, @RowsDeleted = @Del;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @Err NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC CH_ADMIN.etl.usp_Step_End @StepId, N'Échec', @Message = @Err;
        THROW;
    END CATCH;
END;
GO

PRINT N'07 - CH_DWH procédures : OK';
