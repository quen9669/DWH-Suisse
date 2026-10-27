/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 08_DWH_Vues_Cube.sql
   Base        : CH_DWH
   Rôle        : Couche de vues "cube.*" lue par le modèle SSAS.
                 Bonne pratique : le cube ne lit JAMAIS les tables directement.
                 Si une table change, on adapte la vue sans toucher au cube.
   Ré-exécutable : OUI
   ============================================================================= */
USE CH_DWH;
GO

CREATE OR ALTER VIEW cube.vw_Date
AS
SELECT d.DateKey, d.[Date], d.[Year], d.[Quarter], d.QuarterLabel,
       d.[Year] * 10 + d.[Quarter] AS YearQuarter,   -- colonne de tri des trimestres
       d.[Month], d.MonthName,
       d.YearMonth, d.YearMonthLabel, d.IsoWeek, d.DayOfMonth, d.DayOfWeek, d.DayName,
       d.IsWeekend, d.IsHoliday, d.HolidayName, d.DayType
  FROM dim.[Date] AS d
 -- on limite le calendrier aux années réellement chargées (modèle plus léger)
 WHERE d.[Year] BETWEEN (SELECT COALESCE(MIN(DateKey) / 10000, YEAR(GETDATE())) FROM fact.StopEvent)
                    AND (SELECT COALESCE(MAX(DateKey) / 10000, YEAR(GETDATE())) FROM fact.StopEvent);
GO

CREATE OR ALTER VIEW cube.vw_Heure
AS
SELECT t.TimeKey, t.[Hour], t.[Minute], t.TimeLabel, t.HourLabel, t.TimeBand, t.TimeBandOrder
  FROM dim.[Time] AS t;
GO

CREATE OR ALTER VIEW cube.vw_Canton
AS
SELECT c.CantonKey, c.CantonAbbr, c.CantonName, c.Capital, c.LanguageRegion, c.Latitude, c.Longitude
  FROM dim.Canton AS c;
GO

CREATE OR ALTER VIEW cube.vw_Gare
AS
SELECT s.StationKey, s.Uic, s.StationName,
       CONCAT(s.StationName, N' (', s.Uic, N')') AS StationLabel,
       s.Abbreviation, COALESCE(s.CountryIso, N'?') AS CountryIso,
       COALESCE(s.MunicipalityName, N'(inconnue)') AS MunicipalityName,
       COALESCE(s.DistrictName, N'(inconnu)')      AS DistrictName,
       s.MeansOfTransport, s.OwnerAbbr, s.Latitude, s.Longitude, s.Altitude,
       s.IsInferred, s.ValidFrom, s.ValidTo, s.IsCurrent
  FROM dim.Station AS s;
GO

CREATE OR ALTER VIEW cube.vw_Operateur
AS
SELECT o.OperatorKey, o.OperatorAbbr, o.OperatorName
  FROM dim.Operator AS o;
GO

CREATE OR ALTER VIEW cube.vw_Ligne
AS
SELECT l.LineKey, l.LineCode, COALESCE(l.ServiceType, N'?') AS ServiceType, l.LineLabel
  FROM dim.Line AS l;
GO

CREATE OR ALTER VIEW cube.vw_Mode
AS
SELECT m.TransportModeKey, m.ModeLabel, m.ModeCategory
  FROM dim.TransportMode AS m;
GO

CREATE OR ALTER VIEW cube.vw_StatutMesure
AS
SELECT s.StatusKey, s.StatusLabel, s.IsMeasured
  FROM dim.MeasureStatus AS s;
GO

CREATE OR ALTER VIEW cube.vw_Passage
AS
SELECT f.DateKey, f.TimeKey,
       CAST(CASE WHEN f.TimeKey < 0 THEN -1 ELSE (f.TimeKey / 100) * 100 END AS SMALLINT) AS HourKey,  -- HH00 : lien avec la météo horaire
       f.StationKey, f.CantonKey, f.OperatorKey, f.LineKey,
       f.TransportModeKey, f.ArrivalStatusKey, f.DepartureStatusKey,
       f.TripId,
       CAST(f.ReferenceDelaySec / 60.0 AS DECIMAL(9,2)) AS DelayMinutes,
       CAST(CASE WHEN f.ReferenceDelaySec > 0 THEN f.ReferenceDelaySec ELSE 0 END / 60.0
            AS DECIMAL(9,2))                            AS PositiveDelayMinutes,
       f.IsAdditionalTrip, f.IsPassThrough,
       f.StopCount, f.CancelledCount, f.MeasuredCount, f.PunctualCount
  FROM fact.StopEvent AS f;
GO

CREATE OR ALTER VIEW cube.vw_Meteo
AS
SELECT w.DateKey, w.TimeKey, w.CantonKey,
       w.Temperature, w.Precipitation, w.Snowfall, w.WindSpeed,
       CASE WHEN w.Precipitation >= 0.5 OR w.Snowfall > 0 THEN 1 ELSE 0 END AS IsWetHour
  FROM fact.WeatherHourly AS w;
GO

PRINT N'08 - CH_DWH vues du cube : OK';
