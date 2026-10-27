/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 06_DWH_Referentiels.sql
   Base        : CH_DWH
   Rôle        : Remplit les dimensions "statiques" (qui ne viennent pas des
                 fichiers sources) : calendrier, heures, cantons, modes de
                 transport, statuts, et les lignes "Inconnu" (clé -1).
   Ré-exécutable : OUI (MERGE / contrôles d'existence)
   ============================================================================= */
USE CH_DWH;
GO

/* ---------------------------------------------------------------------------
   Fonction : dimanche de Pâques (algorithme de Meeus/Jones/Butcher)
   Sert à calculer les jours fériés mobiles (Vendredi saint, Ascension...).
   --------------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION etl.fn_EasterSunday (@Year INT)
RETURNS DATE
AS
BEGIN
    DECLARE @a INT = @Year % 19,
            @b INT = @Year / 100,
            @c INT = @Year % 100;
    DECLARE @d INT = @b / 4,
            @e INT = @b % 4,
            @f INT = (@b + 8) / 25;
    DECLARE @g INT = (@b - @f + 1) / 3;
    DECLARE @h INT = (19 * @a + @b - @d - @g + 15) % 30;
    DECLARE @i INT = @c / 4,
            @k INT = @c % 4;
    DECLARE @l INT = (32 + 2 * @e + 2 * @i - @h - @k) % 7;
    DECLARE @m INT = (@a + 11 * @h + 22 * @l) / 451;
    DECLARE @month INT = (@h + @l - 7 * @m + 114) / 31,
            @day   INT = ((@h + @l - 7 * @m + 114) % 31) + 1;
    RETURN DATEFROMPARTS(@Year, @month, @day);
END;
GO

/* ---------------------------------------------------------------------------
   Procédure : remplit le calendrier entre deux dates (ajoute les jours manquants)
   --------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimDate
    @From DATE,
    @To   DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH n AS
    (
        SELECT TOP (DATEDIFF(DAY, @From, @To) + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
          FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
    ),
    d AS
    (
        SELECT DATEADD(DAY, n.i, @From) AS dt FROM n
    ),
    h AS  -- jours fériés fédéraux et largement chômés en Suisse
    (
        SELECT d.dt,
               e.Easter,
               CASE
                   WHEN MONTH(d.dt) = 1  AND DAY(d.dt) = 1  THEN N'Nouvel An'
                   WHEN MONTH(d.dt) = 8  AND DAY(d.dt) = 1  THEN N'Fête nationale'
                   WHEN MONTH(d.dt) = 12 AND DAY(d.dt) = 25 THEN N'Noël'
                   WHEN MONTH(d.dt) = 12 AND DAY(d.dt) = 26 THEN N'Saint-Étienne'
                   WHEN d.dt = DATEADD(DAY, -2, e.Easter)  THEN N'Vendredi saint'
                   WHEN d.dt = DATEADD(DAY,  1, e.Easter)  THEN N'Lundi de Pâques'
                   WHEN d.dt = DATEADD(DAY, 39, e.Easter)  THEN N'Ascension'
                   WHEN d.dt = DATEADD(DAY, 50, e.Easter)  THEN N'Lundi de Pentecôte'
               END AS HolidayName,
               (DATEDIFF(DAY, '19000101', d.dt) % 7) + 1 AS Dow   -- 1 = lundi (indépendant de SET DATEFIRST)
          FROM d
         CROSS APPLY (SELECT etl.fn_EasterSunday(YEAR(d.dt)) AS Easter) AS e
    )
    INSERT INTO dim.[Date]
           (DateKey, [Date], [Year], [Quarter], QuarterLabel, [Month], MonthName, YearMonth,
            YearMonthLabel, IsoWeek, DayOfMonth, DayOfWeek, DayName, IsWeekend, IsHoliday,
            HolidayName, DayType)
    SELECT YEAR(h.dt) * 10000 + MONTH(h.dt) * 100 + DAY(h.dt),
           h.dt,
           YEAR(h.dt),
           DATEPART(QUARTER, h.dt),
           CONCAT(N'T', DATEPART(QUARTER, h.dt), N' ', YEAR(h.dt)),
           MONTH(h.dt),
           CHOOSE(MONTH(h.dt), N'janvier', N'février', N'mars', N'avril', N'mai', N'juin',
                  N'juillet', N'août', N'septembre', N'octobre', N'novembre', N'décembre'),
           YEAR(h.dt) * 100 + MONTH(h.dt),
           CONCAT(CHOOSE(MONTH(h.dt), N'janv.', N'févr.', N'mars', N'avr.', N'mai', N'juin',
                  N'juil.', N'août', N'sept.', N'oct.', N'nov.', N'déc.'), N' ', YEAR(h.dt)),
           DATEPART(ISO_WEEK, h.dt),
           DAY(h.dt),
           h.Dow,
           CHOOSE(h.Dow, N'lundi', N'mardi', N'mercredi', N'jeudi', N'vendredi', N'samedi', N'dimanche'),
           CASE WHEN h.Dow IN (6, 7) THEN 1 ELSE 0 END,
           CASE WHEN h.HolidayName IS NOT NULL THEN 1 ELSE 0 END,
           h.HolidayName,
           CASE WHEN h.Dow = 7 OR h.HolidayName IS NOT NULL THEN N'Dimanche ou férié'
                WHEN h.Dow = 6 THEN N'Samedi'
                ELSE N'Jour ouvrable' END
      FROM h
     WHERE NOT EXISTS (SELECT 1 FROM dim.[Date] AS x WHERE x.[Date] = h.dt);

    SELECT @@ROWCOUNT AS RowsInserted;
END;
GO

EXEC etl.usp_Load_DimDate @From = '2020-01-01', @To = '2035-12-31';
GO

/* ---------------------------------------------------------------------------
   dim.Time : 1440 minutes + "Inconnu"
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dim.[Time])
BEGIN
    ;WITH n AS
    (
        SELECT TOP (1440) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS m
          FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
    )
    INSERT INTO dim.[Time] (TimeKey, [Hour], [Minute], TimeLabel, HourLabel, TimeBand, TimeBandOrder)
    SELECT (n.m / 60) * 100 + (n.m % 60),
           n.m / 60,
           n.m % 60,
           CONCAT(RIGHT(CONCAT(N'0', n.m / 60), 2), N':', RIGHT(CONCAT(N'0', n.m % 60), 2)),
           CONCAT(RIGHT(CONCAT(N'0', n.m / 60), 2), N'h'),
           CASE WHEN n.m / 60 < 6  THEN N'Nuit (00h-06h)'
                WHEN n.m / 60 < 9  THEN N'Pointe du matin (06h-09h)'
                WHEN n.m / 60 < 16 THEN N'Journée (09h-16h)'
                WHEN n.m / 60 < 19 THEN N'Pointe du soir (16h-19h)'
                ELSE N'Soirée (19h-24h)' END,
           CASE WHEN n.m / 60 < 6  THEN 1
                WHEN n.m / 60 < 9  THEN 2
                WHEN n.m / 60 < 16 THEN 3
                WHEN n.m / 60 < 19 THEN 4
                ELSE 5 END
      FROM n;

    INSERT INTO dim.[Time] (TimeKey, [Hour], [Minute], TimeLabel, HourLabel, TimeBand, TimeBandOrder)
    VALUES (-1, NULL, NULL, N'Inconnu', N'Inconnu', N'Inconnu', 99);
END;
GO

/* ---------------------------------------------------------------------------
   dim.Canton : 26 cantons (clé = n° officiel OFS) + Inconnu / Étranger
   Coordonnées = chef-lieu (utilisées pour la météo, voir scripts/ref/cantons.csv)
   --------------------------------------------------------------------------- */
MERGE dim.Canton AS t
USING (VALUES
    ( 1, N'ZH', N'Zurich',               N'Zurich',       N'Suisse alémanique', 47.376900, 8.541700),
    ( 2, N'BE', N'Berne',                N'Berne',        N'Suisse alémanique', 46.948000, 7.447400),
    ( 3, N'LU', N'Lucerne',              N'Lucerne',      N'Suisse alémanique', 47.050200, 8.309300),
    ( 4, N'UR', N'Uri',                  N'Altdorf',      N'Suisse alémanique', 46.880400, 8.644400),
    ( 5, N'SZ', N'Schwytz',              N'Schwytz',      N'Suisse alémanique', 47.020700, 8.653000),
    ( 6, N'OW', N'Obwald',               N'Sarnen',       N'Suisse alémanique', 46.896100, 8.245600),
    ( 7, N'NW', N'Nidwald',              N'Stans',        N'Suisse alémanique', 46.958000, 8.366000),
    ( 8, N'GL', N'Glaris',               N'Glaris',       N'Suisse alémanique', 47.040400, 9.067900),
    ( 9, N'ZG', N'Zoug',                 N'Zoug',         N'Suisse alémanique', 47.166200, 8.515500),
    (10, N'FR', N'Fribourg',             N'Fribourg',     N'Suisse romande',    46.806500, 7.162000),
    (11, N'SO', N'Soleure',              N'Soleure',      N'Suisse alémanique', 47.208800, 7.532300),
    (12, N'BS', N'Bâle-Ville',           N'Bâle',         N'Suisse alémanique', 47.559600, 7.588600),
    (13, N'BL', N'Bâle-Campagne',        N'Liestal',      N'Suisse alémanique', 47.484000, 7.735000),
    (14, N'SH', N'Schaffhouse',          N'Schaffhouse',  N'Suisse alémanique', 47.697300, 8.634900),
    (15, N'AR', N'Appenzell Rh.-Ext.',   N'Herisau',      N'Suisse alémanique', 47.386100, 9.279200),
    (16, N'AI', N'Appenzell Rh.-Int.',   N'Appenzell',    N'Suisse alémanique', 47.331600, 9.409400),
    (17, N'SG', N'Saint-Gall',           N'Saint-Gall',   N'Suisse alémanique', 47.424500, 9.376700),
    (18, N'GR', N'Grisons',              N'Coire',        N'Suisse alémanique', 46.849900, 9.532900),
    (19, N'AG', N'Argovie',              N'Aarau',        N'Suisse alémanique', 47.392500, 8.044200),
    (20, N'TG', N'Thurgovie',            N'Frauenfeld',   N'Suisse alémanique', 47.553600, 8.898700),
    (21, N'TI', N'Tessin',               N'Bellinzone',   N'Suisse italienne',  46.194600, 9.024400),
    (22, N'VD', N'Vaud',                 N'Lausanne',     N'Suisse romande',    46.519700, 6.632300),
    (23, N'VS', N'Valais',               N'Sion',         N'Suisse romande',    46.233100, 7.360600),
    (24, N'NE', N'Neuchâtel',            N'Neuchâtel',    N'Suisse romande',    46.990000, 6.929300),
    (25, N'GE', N'Genève',               N'Genève',       N'Suisse romande',    46.204400, 6.143200),
    (26, N'JU', N'Jura',                 N'Delémont',     N'Suisse romande',    47.364900, 7.344500),
    (-1, N'??', N'Inconnu / étranger',   N'-',            N'Hors Suisse / inconnu', NULL, NULL)
) AS s (CantonKey, CantonAbbr, CantonName, Capital, LanguageRegion, Latitude, Longitude)
ON t.CantonKey = s.CantonKey
WHEN MATCHED THEN UPDATE SET
     CantonAbbr = s.CantonAbbr, CantonName = s.CantonName, Capital = s.Capital,
     LanguageRegion = s.LanguageRegion, Latitude = s.Latitude, Longitude = s.Longitude
WHEN NOT MATCHED THEN INSERT (CantonKey, CantonAbbr, CantonName, Capital, LanguageRegion, Latitude, Longitude)
     VALUES (s.CantonKey, s.CantonAbbr, s.CantonName, s.Capital, s.LanguageRegion, s.Latitude, s.Longitude);
GO

/* ---------------------------------------------------------------------------
   dim.MeasureStatus : statuts de l'heure réelle (documentation officielle)
   --------------------------------------------------------------------------- */
MERGE dim.MeasureStatus AS t
USING (VALUES
    ( 1, N'REAL',       N'Réel (mesuré)',                1),
    ( 2, N'GESCHAETZT', N'Estimé',                       1),
    ( 3, N'PROGNOSE',   N'Prévision seulement',          0),
    ( 4, N'UNBEKANNT',  N'Inconnu (aucune donnée)',      0),
    ( 5, N'SANS_OBJET', N'Sans objet (pas d''horaire)',  0),
    (-1, N'?',          N'Statut non reconnu',           0)
) AS s (StatusKey, StatusCode, StatusLabel, IsMeasured)
ON t.StatusKey = s.StatusKey
WHEN MATCHED THEN UPDATE SET StatusCode = s.StatusCode, StatusLabel = s.StatusLabel, IsMeasured = s.IsMeasured
WHEN NOT MATCHED THEN INSERT (StatusKey, StatusCode, StatusLabel, IsMeasured)
     VALUES (s.StatusKey, s.StatusCode, s.StatusLabel, s.IsMeasured);
GO

/* ---------------------------------------------------------------------------
   dim.TransportMode : traduction des codes allemands de la source
   Les codes inconnus seront ajoutés automatiquement par le chargement.
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dim.TransportMode WHERE TransportModeKey = -1)
BEGIN
    SET IDENTITY_INSERT dim.TransportMode ON;
    INSERT INTO dim.TransportMode (TransportModeKey, ProductCode, ModeLabel, ModeCategory)
    VALUES (-1, N'?', N'Inconnu', N'Inconnu');
    SET IDENTITY_INSERT dim.TransportMode OFF;
END;
GO

MERGE dim.TransportMode AS t
USING (VALUES
    (N'Zug',            N'Train',                N'Ferroviaire'),
    (N'Metro',          N'Métro',                N'Ferroviaire'),
    (N'Tram',           N'Tram',                 N'Ferroviaire'),
    (N'Zahnradbahn',    N'Train à crémaillère',  N'Montagne'),
    (N'Standseilbahn',  N'Funiculaire',          N'Montagne'),
    (N'Luftseilbahn',   N'Téléphérique',         N'Montagne'),
    (N'Gondelbahn',     N'Télécabine',           N'Montagne'),
    (N'Sesselbahn',     N'Télésiège',            N'Montagne'),
    (N'Bus',            N'Bus',                  N'Routier'),
    (N'Taxi',           N'Taxi / à la demande',  N'Routier'),
    (N'Schiff',         N'Bateau',               N'Lacustre')
) AS s (ProductCode, ModeLabel, ModeCategory)
ON t.ProductCode = s.ProductCode
WHEN MATCHED THEN UPDATE SET ModeLabel = s.ModeLabel, ModeCategory = s.ModeCategory
WHEN NOT MATCHED THEN INSERT (ProductCode, ModeLabel, ModeCategory)
     VALUES (s.ProductCode, s.ModeLabel, s.ModeCategory);
GO

/* ---------------------------------------------------------------------------
   Lignes "Inconnu" (clé -1) des dimensions alimentées par les sources
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM dim.Operator WHERE OperatorKey = -1)
BEGIN
    SET IDENTITY_INSERT dim.Operator ON;
    INSERT INTO dim.Operator (OperatorKey, OperatorId, OperatorAbbr, OperatorName)
    VALUES (-1, N'?', N'?', N'Opérateur inconnu');
    SET IDENTITY_INSERT dim.Operator OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM dim.Line WHERE LineKey = -1)
BEGIN
    SET IDENTITY_INSERT dim.Line ON;
    INSERT INTO dim.Line (LineKey, OperatorId, ProductCode, LineCode, ServiceType, LineLabel)
    VALUES (-1, N'?', N'?', N'?', NULL, N'Ligne inconnue');
    SET IDENTITY_INSERT dim.Line OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM dim.Station WHERE StationKey = -1)
BEGIN
    SET IDENTITY_INSERT dim.Station ON;
    INSERT INTO dim.Station (StationKey, Uic, StationName, CantonAbbr, IsInferred, ValidFrom, ValidTo, IsCurrent)
    VALUES (-1, -1, N'Arrêt inconnu', N'??', 0, '1900-01-01', '9999-12-31', 1);
    SET IDENTITY_INSERT dim.Station OFF;
END;
GO

PRINT N'06 - CH_DWH référentiels : OK';
