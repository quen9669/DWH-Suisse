/* =============================================================================
   Projet      : DWH Suisse - Transports publics
   Script      : 09_Securite.sql
   Rôle        : Donne aux comptes de SERVICE Windows les droits nécessaires :
                 - SSAS (le cube) doit LIRE la base CH_DWH pour se "traiter"
                 - SQL Server Agent (exécution planifiée des packages) doit
                   lire/écrire les 4 bases
                 Environnement de DÉVELOPPEMENT : droits volontairement simples.
                 En entreprise, on créerait des rôles plus fins.
   Ré-exécutable : OUI. Si un compte n'existe pas sur votre PC (ex. SSAS non
                 installé), le script l'indique et continue.
   ============================================================================= */
USE master;
GO

DECLARE @Accounts TABLE (LoginName SYSNAME, ForWhat NVARCHAR(100));
INSERT INTO @Accounts VALUES
    (N'NT SERVICE\MSSQLServerOLAPService', N'SSAS (instance par défaut)'),
    (N'NT SERVICE\SQLSERVERAGENT',         N'SQL Server Agent (instance par défaut)');

DECLARE @Login SYSNAME, @ForWhat NVARCHAR(100), @Sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT LoginName, ForWhat FROM @Accounts;
OPEN c;
FETCH NEXT FROM c INTO @Login, @ForWhat;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        IF SUSER_ID(@Login) IS NULL
        BEGIN
            SET @Sql = N'CREATE LOGIN ' + QUOTENAME(@Login) + N' FROM WINDOWS;';
            EXEC (@Sql);
        END;
        PRINT N'Connexion OK : ' + @Login + N' (' + @ForWhat + N')';
    END TRY
    BEGIN CATCH
        PRINT N'IGNORÉ : ' + @Login + N' -> ' + ERROR_MESSAGE();
    END CATCH;
    FETCH NEXT FROM c INTO @Login, @ForWhat;
END;
CLOSE c;
DEALLOCATE c;
GO

/* ---------- SQL Agent : droit de lire des fichiers (OPENROWSET BULK, météo) ---------- */
IF SUSER_ID(N'NT SERVICE\SQLSERVERAGENT') IS NOT NULL
BEGIN
    ALTER SERVER ROLE bulkadmin ADD MEMBER [NT SERVICE\SQLSERVERAGENT];
    PRINT N'SQL Agent : membre de bulkadmin';
END;
GO

/* ---------- SSAS : lecture seule sur CH_DWH ---------- */
USE CH_DWH;
GO
IF SUSER_ID(N'NT SERVICE\MSSQLServerOLAPService') IS NOT NULL
BEGIN
    IF USER_ID(N'NT SERVICE\MSSQLServerOLAPService') IS NULL
        CREATE USER [NT SERVICE\MSSQLServerOLAPService] FOR LOGIN [NT SERVICE\MSSQLServerOLAPService];
    ALTER ROLE db_datareader ADD MEMBER [NT SERVICE\MSSQLServerOLAPService];
    PRINT N'SSAS : lecture sur CH_DWH accordée';
END;
GO

/* ---------- SQL Server Agent : propriétaire des 4 bases (dev uniquement) ---------- */
DECLARE @db SYSNAME, @Sql NVARCHAR(MAX);
DECLARE d CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE name IN (N'CH_ADMIN', N'CH_ODS', N'CH_STG', N'CH_DWH');
OPEN d;
FETCH NEXT FROM d INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF SUSER_ID(N'NT SERVICE\SQLSERVERAGENT') IS NOT NULL
    BEGIN
        SET @Sql = N'USE ' + QUOTENAME(@db) + N';
            IF USER_ID(N''NT SERVICE\SQLSERVERAGENT'') IS NULL
                CREATE USER [NT SERVICE\SQLSERVERAGENT] FOR LOGIN [NT SERVICE\SQLSERVERAGENT];
            ALTER ROLE db_owner ADD MEMBER [NT SERVICE\SQLSERVERAGENT];';
        EXEC (@Sql);
        PRINT N'SQL Agent : db_owner sur ' + @db;
    END;
    FETCH NEXT FROM d INTO @db;
END;
CLOSE d;
DEALLOCATE d;
GO

PRINT N'09 - Sécurité : OK';
