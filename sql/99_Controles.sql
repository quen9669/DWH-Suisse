/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 99_Controles.sql
   Rôle        : Requêtes de CONTRÔLE à lancer à la main dans SSMS après un
                 chargement. Sélectionnez une requête puis F5.
   ============================================================================= */

/* 1. Les 10 derniers lots : statut et durée */
SELECT TOP (10) * FROM CH_ADMIN.etl.vw_Suivi_Lots;

/* 2. Détail des étapes du dernier lot */
SELECT * FROM CH_ADMIN.etl.vw_Suivi_Etapes
 WHERE BatchId = (SELECT MAX(BatchId) FROM CH_ADMIN.etl.Batch)
 ORDER BY StepId;

/* 3. Fichiers chargés et leur statut (ODS_OK = en attente d'intégration) */
SELECT SourceType, [Status], COUNT(*) AS NbFichiers, SUM(RowsOds) AS NbLignes
  FROM CH_ADMIN.etl.FileLog
 GROUP BY SourceType, [Status];

/* 4. Rejets de qualité du dernier lot, par motif */
SELECT RejectReason, COUNT(*) AS NbLignes
  FROM CH_STG.stg.Istdaten_Rejet
 WHERE _BatchId = (SELECT MAX(_BatchId) FROM CH_STG.stg.Istdaten_Rejet)
 GROUP BY RejectReason
 ORDER BY NbLignes DESC;

/* 5. Réconciliation ODS -> STG -> DWH par jour (les chiffres doivent "tomber juste") */
SELECT d.[Date],
       (SELECT COUNT_BIG(*) FROM CH_ODS.ods.Istdaten AS o
         WHERE TRY_CONVERT(DATE, o.BETRIEBSTAG, 104) = d.[Date])           AS Lignes_ODS,
       (SELECT COUNT_BIG(*) FROM CH_STG.stg.Istdaten_Rejet AS r
         WHERE TRY_CONVERT(DATE, r.BETRIEBSTAG, 104) = d.[Date])           AS Lignes_Rejetees,
       (SELECT COUNT_BIG(*) FROM CH_DWH.fact.StopEvent AS f
         WHERE f.DateKey = d.DateKey)                                       AS Lignes_DWH
  FROM CH_DWH.dim.[Date] AS d
 WHERE d.DateKey IN (SELECT DISTINCT DateKey FROM CH_DWH.fact.StopEvent)
 ORDER BY d.[Date];

/* 6. Faits rattachés à un membre "Inconnu" (-1) : doit rester marginal */
SELECT SUM(CASE WHEN StationKey  = -1 THEN 1 ELSE 0 END) AS SansGare,
       SUM(CASE WHEN OperatorKey = -1 THEN 1 ELSE 0 END) AS SansOperateur,
       SUM(CASE WHEN LineKey     = -1 THEN 1 ELSE 0 END) AS SansLigne,
       SUM(CASE WHEN CantonKey   = -1 THEN 1 ELSE 0 END) AS HorsSuisseOuInconnu,
       COUNT_BIG(*)                                      AS Total
  FROM CH_DWH.fact.StopEvent;

/* 7. Historique SCD2 : gares ayant plusieurs versions */
SELECT TOP (50) Uic, StationName, ValidFrom, ValidTo, IsCurrent
  FROM CH_DWH.dim.Station
 WHERE Uic IN (SELECT Uic FROM CH_DWH.dim.Station GROUP BY Uic HAVING COUNT(*) > 1)
 ORDER BY Uic, ValidFrom;

/* 8. Premier indicateur métier : ponctualité des trains par jour */
SELECT d.[Date],
       SUM(f.MeasuredCount)                                         AS ArretsMesures,
       CAST(100.0 * SUM(f.PunctualCount) / NULLIF(SUM(f.MeasuredCount), 0) AS DECIMAL(5,2)) AS PonctualitePct
  FROM CH_DWH.fact.StopEvent AS f
  JOIN CH_DWH.dim.[Date] AS d ON d.DateKey = f.DateKey
  JOIN CH_DWH.dim.TransportMode AS m ON m.TransportModeKey = f.TransportModeKey
 WHERE m.ModeLabel = N'Train'
 GROUP BY d.[Date]
 ORDER BY d.[Date];

/* 9. Modes de transport non traduits (à ajouter dans 06_DWH_Referentiels.sql) */
SELECT * FROM CH_DWH.dim.TransportMode WHERE ModeCategory = N'À classer';
