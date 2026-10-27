/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 05_DWH_Tables.sql
   Base        : CH_DWH
   Rôle        : Tables de l'ENTREPÔT (modèle en étoile).
                 - Dimensions (dim.*) = les axes d'analyse : quand ? où ? qui ? quoi ?
                 - Faits (fact.*)      = les événements mesurés : passages, météo
                 Chaque dimension possède une ligne "Inconnu" (clé -1) pour que
                 tout fait trouve toujours une correspondance.
   Ré-exécutable : OUI
   ============================================================================= */
USE CH_DWH;
GO

/* ---------- dim.Date : calendrier (1 ligne par jour) ---------- */
IF OBJECT_ID(N'dim.Date', N'U') IS NULL
CREATE TABLE dim.[Date]
(
    DateKey          INT           NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY,  -- AAAAMMJJ
    [Date]           DATE          NOT NULL,
    [Year]           SMALLINT      NOT NULL,
    [Quarter]        TINYINT       NOT NULL,
    QuarterLabel     NVARCHAR(10)  NOT NULL,   -- T1 2026
    [Month]          TINYINT       NOT NULL,
    MonthName        NVARCHAR(20)  NOT NULL,   -- octobre
    YearMonth        INT           NOT NULL,   -- 202610
    YearMonthLabel   NVARCHAR(20)  NOT NULL,   -- oct. 2026
    IsoWeek          TINYINT       NOT NULL,
    DayOfMonth       TINYINT       NOT NULL,
    DayOfWeek        TINYINT       NOT NULL,   -- 1 = lundi ... 7 = dimanche
    DayName          NVARCHAR(20)  NOT NULL,
    IsWeekend        BIT           NOT NULL,
    IsHoliday        BIT           NOT NULL,
    HolidayName      NVARCHAR(50)  NULL,
    DayType          NVARCHAR(30)  NOT NULL    -- Jour ouvrable / Samedi / Dimanche ou férié
);
GO

/* ---------- dim.Time : heure de la journée (1 ligne par minute) ---------- */
IF OBJECT_ID(N'dim.Time', N'U') IS NULL
CREATE TABLE dim.[Time]
(
    TimeKey          SMALLINT      NOT NULL CONSTRAINT PK_DimTime PRIMARY KEY,  -- HHMM (ex. 0732)
    [Hour]           TINYINT       NULL,
    [Minute]         TINYINT       NULL,
    TimeLabel        NVARCHAR(10)  NOT NULL,   -- 07:32
    HourLabel        NVARCHAR(10)  NOT NULL,   -- 07h
    TimeBand         NVARCHAR(30)  NOT NULL,   -- Pointe du matin...
    TimeBandOrder    TINYINT       NOT NULL
);
GO

/* ---------- dim.Canton : référentiel des 26 cantons (clé = n° OFS) ---------- */
IF OBJECT_ID(N'dim.Canton', N'U') IS NULL
CREATE TABLE dim.Canton
(
    CantonKey        SMALLINT      NOT NULL CONSTRAINT PK_DimCanton PRIMARY KEY,
    CantonAbbr       NVARCHAR(10)  NOT NULL CONSTRAINT UQ_DimCanton_Abbr UNIQUE,
    CantonName       NVARCHAR(50)  NOT NULL,
    Capital          NVARCHAR(50)  NOT NULL,
    LanguageRegion   NVARCHAR(30)  NOT NULL,   -- Suisse alémanique / romande / italienne
    Latitude         DECIMAL(9,6)  NULL,       -- chef-lieu (sert à la météo)
    Longitude        DECIMAL(9,6)  NULL
);
GO

/* ---------- dim.TransportMode : mode de transport ---------- */
IF OBJECT_ID(N'dim.TransportMode', N'U') IS NULL
CREATE TABLE dim.TransportMode
(
    TransportModeKey SMALLINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimTransportMode PRIMARY KEY,
    ProductCode      NVARCHAR(255) NOT NULL CONSTRAINT UQ_DimTransportMode UNIQUE,  -- code source (Zug, Bus...)
    ModeLabel        NVARCHAR(50)  NOT NULL,   -- libellé français
    ModeCategory     NVARCHAR(30)  NOT NULL,   -- Ferroviaire / Routier / ...
    InsertBatchId    INT           NULL
);
GO

/* ---------- dim.MeasureStatus : qualité de l'horaire réel ---------- */
IF OBJECT_ID(N'dim.MeasureStatus', N'U') IS NULL
CREATE TABLE dim.MeasureStatus
(
    StatusKey        SMALLINT      NOT NULL CONSTRAINT PK_DimMeasureStatus PRIMARY KEY,
    StatusCode       NVARCHAR(20)  NOT NULL CONSTRAINT UQ_DimMeasureStatus UNIQUE,
    StatusLabel      NVARCHAR(50)  NOT NULL,
    IsMeasured       BIT           NOT NULL    -- 1 = l'heure réelle a été mesurée/estimée
);
GO

/* ---------- dim.Operator : entreprise de transport (SCD type 1) ---------- */
IF OBJECT_ID(N'dim.Operator', N'U') IS NULL
CREATE TABLE dim.Operator
(
    OperatorKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimOperator PRIMARY KEY,
    OperatorId       NVARCHAR(255) NOT NULL CONSTRAINT UQ_DimOperator UNIQUE,  -- clé métier
    OperatorAbbr     NVARCHAR(255) NOT NULL,
    OperatorName     NVARCHAR(255) NOT NULL,
    InsertBatchId    INT           NULL,
    UpdateBatchId    INT           NULL
);
GO

/* ---------- dim.Line : ligne (SCD type 1) ---------- */
IF OBJECT_ID(N'dim.Line', N'U') IS NULL
CREATE TABLE dim.Line
(
    LineKey          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimLine PRIMARY KEY,
    OperatorId       NVARCHAR(255) NOT NULL,   -- clé métier = opérateur + mode + ligne
    ProductCode      NVARCHAR(255) NOT NULL,
    LineCode         NVARCHAR(255) NOT NULL,
    ServiceType      NVARCHAR(255) NULL,       -- IC, IR, RE, S, B...
    LineLabel        NVARCHAR(400) NOT NULL,   -- libellé affiché (ex. "SBB - IC1")
    InsertBatchId    INT           NULL,
    UpdateBatchId    INT           NULL,
    CONSTRAINT UQ_DimLine UNIQUE (OperatorId, ProductCode, LineCode)
);
GO

/* ---------- dim.Station : point d'arrêt (SCD type 2 = historisé) ----------
   Quand un attribut suivi change (nom, commune, coordonnées...), on ne
   l'écrase pas : on ferme l'ancienne version (ValidTo) et on en crée une
   nouvelle. Les faits passés restent rattachés à la version de l'époque.
   IsInferred = 1 : arrêt vu dans les passages mais absent du référentiel
   ("membre déduit"), complété automatiquement quand il arrive.            */
IF OBJECT_ID(N'dim.Station', N'U') IS NULL
CREATE TABLE dim.Station
(
    StationKey       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimStation PRIMARY KEY,
    Uic              INT           NOT NULL,   -- clé métier
    Sloid            NVARCHAR(255) NULL,
    StationName      NVARCHAR(255) NOT NULL,
    Abbreviation     NVARCHAR(255) NULL,
    CountryIso       NVARCHAR(10)  NULL,
    CantonAbbr       NVARCHAR(10)  NULL,
    CantonName       NVARCHAR(255) NULL,
    DistrictName     NVARCHAR(255) NULL,
    MunicipalityName NVARCHAR(255) NULL,
    LocalityName     NVARCHAR(255) NULL,
    MeansOfTransport NVARCHAR(255) NULL,
    IsStopPoint      BIT           NOT NULL CONSTRAINT DF_DimStation_IsStop DEFAULT (0),
    OwnerAbbr        NVARCHAR(255) NULL,
    OwnerName        NVARCHAR(255) NULL,
    Latitude         DECIMAL(9,6)  NULL,
    Longitude        DECIMAL(9,6)  NULL,
    Altitude         DECIMAL(7,1)  NULL,
    HashDiff         VARBINARY(32) NULL,
    IsInferred       BIT           NOT NULL CONSTRAINT DF_DimStation_IsInferred DEFAULT (0),
    ValidFrom        DATE          NOT NULL,   -- début de validité (inclus)
    ValidTo          DATE          NOT NULL,   -- fin de validité (exclue) ; 9999-12-31 = version courante
    IsCurrent        BIT           NOT NULL,
    InsertBatchId    INT           NULL,
    UpdateBatchId    INT           NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_DimStation_Uic_ValidFrom')
    CREATE UNIQUE INDEX UX_DimStation_Uic_ValidFrom ON dim.Station (Uic, ValidFrom)
    INCLUDE (ValidTo, CantonAbbr);
GO

/* ---------- fact.StopEvent : 1 ligne = 1 passage d'un trajet à un arrêt ----------
   Volume : ~2,5 millions de lignes par jour -> index COLUMNSTORE.            */
IF OBJECT_ID(N'fact.StopEvent', N'U') IS NULL
CREATE TABLE fact.StopEvent
(
    DateKey             INT           NOT NULL,   -- jour d'exploitation
    TimeKey             SMALLINT      NOT NULL,   -- heure prévue (arrivée sinon départ)
    StationKey          INT           NOT NULL,
    CantonKey           SMALLINT      NOT NULL,
    OperatorKey         INT           NOT NULL,
    LineKey             INT           NOT NULL,
    TransportModeKey    SMALLINT      NOT NULL,
    ArrivalStatusKey    SMALLINT      NOT NULL,
    DepartureStatusKey  SMALLINT      NOT NULL,
    TripId              NVARCHAR(255) NOT NULL,   -- dimension "dégénérée" (identifiant du trajet)
    ArrivalPlanned      DATETIME2(0)  NULL,
    ArrivalActual       DATETIME2(0)  NULL,
    DeparturePlanned    DATETIME2(0)  NULL,
    DepartureActual     DATETIME2(0)  NULL,
    ArrivalDelaySec     INT           NULL,
    DepartureDelaySec   INT           NULL,
    ReferenceDelaySec   INT           NULL,       -- retard retenu pour les indicateurs
    IsAdditionalTrip    BIT           NOT NULL,
    IsPassThrough       BIT           NOT NULL,
    IsDelayOutlier      BIT           NOT NULL,
    StopCount           TINYINT       NOT NULL,   -- toujours 1 (pratique pour sommer)
    CancelledCount      TINYINT       NOT NULL,   -- 1 si supprimé
    MeasuredCount       TINYINT       NOT NULL,   -- 1 si retard mesuré et fiable
    PunctualCount       TINYINT       NOT NULL,   -- 1 si mesuré ET retard < 3 min
    _BatchId            INT           NOT NULL,
    _LoadDtm            DATETIME2(0)  NOT NULL CONSTRAINT DF_FactStopEvent_LoadDtm DEFAULT (SYSDATETIME())
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'CCI_fact_StopEvent')
    CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_StopEvent ON fact.StopEvent;
GO

/* ---------- fact.WeatherHourly : météo horaire par canton ---------- */
IF OBJECT_ID(N'fact.WeatherHourly', N'U') IS NULL
CREATE TABLE fact.WeatherHourly
(
    DateKey          INT           NOT NULL,
    TimeKey          SMALLINT      NOT NULL,   -- HH00
    CantonKey        SMALLINT      NOT NULL,
    Temperature      DECIMAL(5,1)  NULL,
    Precipitation    DECIMAL(6,2)  NULL,
    Snowfall         DECIMAL(6,2)  NULL,
    WindSpeed        DECIMAL(5,1)  NULL,
    _BatchId         INT           NOT NULL,
    _LoadDtm         DATETIME2(0)  NOT NULL CONSTRAINT DF_FactWeather_LoadDtm DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_FactWeatherHourly PRIMARY KEY (DateKey, TimeKey, CantonKey)
);
GO

PRINT N'05 - CH_DWH tables : OK';
