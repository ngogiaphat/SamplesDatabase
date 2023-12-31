-- This script creates comparable disk-based and memory-optimized tables, as well as corresponding stored procedures
--   for vehicle location insertion.
-- It then compares the performance of single-threaded inserts (50K rows):
--   - into a disk-based table
--   - into a memory-optimized table
--   - into a memory-optimized table, with rows generated in a natively compiled stored procedure
--
-- Before running the script, make sure to connect to a user database.
SET NOCOUNT ON;
SET XACT_ABORT ON;
DROP PROCEDURE IF EXISTS InMemory.Insert50ThousandVehicleLocations
DROP PROCEDURE IF EXISTS InMemory.InsertVehicleLocation
DROP PROCEDURE IF EXISTS OnDisk.InsertVehicleLocation
DROP TABLE IF EXISTS InMemory.VehicleLocations
DROP TABLE IF EXISTS OnDisk.VehicleLocations
GO
DROP SCHEMA IF EXISTS InMemory
DROP SCHEMA IF EXISTS OnDisk
GO
-- We then create the disk based table and insert stored procedure
CREATE SCHEMA OnDisk AUTHORIZATION dbo;
GO
CREATE TABLE OnDisk.VehicleLocations(
	VehicleLocationID bigint IDENTITY(1,1) PRIMARY KEY,
	RegistrationNumber nvarchar(20) NOT NULL,
	TrackedWhen datetime2(2) NOT NULL,
	Longitude decimal(18,4) NOT NULL,
	Latitude decimal(18,4) NOT NULL
);
GO
CREATE PROCEDURE OnDisk.InsertVehicleLocation
@RegistrationNumber nvarchar(20),
@TrackedWhen datetime2(2),
@Longitude decimal(18,4),
@Latitude decimal(18,4)
WITH EXECUTE AS OWNER
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	INSERT OnDisk.VehicleLocations(RegistrationNumber, TrackedWhen, Longitude, Latitude)
	VALUES(@RegistrationNumber, @TrackedWhen, @Longitude, @Latitude);
	RETURN 0;
END;
GO
-- And then in-memory and natively-compiled alternatives
CREATE SCHEMA InMemory AUTHORIZATION dbo;
GO
CREATE TABLE InMemory.VehicleLocations(
	VehicleLocationID bigint IDENTITY(1,1) PRIMARY KEY NONCLUSTERED,
	RegistrationNumber nvarchar(20) NOT NULL,
	TrackedWhen datetime2(2) NOT NULL,
	Longitude decimal(18,4) NOT NULL,
	Latitude decimal(18,4) NOT NULL
)
WITH(MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);
GO
CREATE PROCEDURE InMemory.InsertVehicleLocation
@RegistrationNumber nvarchar(20),
@TrackedWhen datetime2(2),
@Longitude decimal(18,4),
@Latitude decimal(18,4)
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS
BEGIN ATOMIC WITH(
	TRANSACTION ISOLATION LEVEL = SNAPSHOT,
	LANGUAGE = N'English'
)
	INSERT InMemory.VehicleLocations(RegistrationNumber, TrackedWhen, Longitude, Latitude)
	VALUES(@RegistrationNumber, @TrackedWhen, @Longitude, @Latitude);
	RETURN 0;
END;
GO
-- Note the time to insert 50 thousand location rows using on-disk
declare @start datetime2
set @start = SYSDATETIME()
DECLARE @RegistrationNumber nvarchar(20);
DECLARE @TrackedWhen datetime2(2);
DECLARE @Longitude decimal(18,4);
DECLARE @Latitude decimal(18,4);
DECLARE @Counter int = 0;
SET NOCOUNT ON;
BEGIN TRAN
WHILE @Counter < 50000
BEGIN
	-- create some dummy data
	SET @RegistrationNumber = N'EA' + RIGHT(N'00' + CAST(@Counter % 100 AS nvarchar(10)), 3) + N'-GL';
	SET @TrackedWhen = SYSDATETIME();
	SET @Longitude = RAND() * 100;
	SET @Latitude = RAND() * 100;
	EXEC OnDisk.InsertVehicleLocation @RegistrationNumber, @TrackedWhen, @Longitude, @Latitude;
	SET @Counter += 1;
END
COMMIT
select datediff(ms,@start, sysdatetime()) as 'insert into disk-based table (in ms)'
GO
-- Now insert the same number of location rows using in-memory and natively compiled
declare @start datetime2
set @start = SYSDATETIME()
DECLARE @RegistrationNumber nvarchar(20);
DECLARE @TrackedWhen datetime2(2);
DECLARE @Longitude decimal(18,4);
DECLARE @Latitude decimal(18,4);
DECLARE @Counter int = 0;
SET NOCOUNT ON;
BEGIN TRAN
WHILE @Counter < 50000
BEGIN
	-- create some dummy data
	SET @RegistrationNumber = N'EA' + RIGHT(N'00' + CAST(@Counter % 100 AS nvarchar(10)), 3) + N'-GL';
	SET @TrackedWhen = SYSDATETIME();
	SET @Longitude = RAND() * 100;
	SET @Latitude = RAND() * 100;
	EXEC InMemory.InsertVehicleLocation @RegistrationNumber, @TrackedWhen, @Longitude, @Latitude;
	SET @Counter += 1;
END
COMMIT
select datediff(ms,@start, sysdatetime()) as 'insert into memory-optimized table (in ms)'
GO
-- Note that while using the in-memory table and natively-compiled procedure is faster, we are still
-- running our main program via interpreted T-SQL and calling the stored procedure via the interop layer.
-- Let's try calling it from another natively-compiled stored procedure.
CREATE PROCEDURE InMemory.Insert50ThousandVehicleLocations
WITH NATIVE_COMPILATION, SCHEMABINDING
AS
BEGIN ATOMIC WITH(
	TRANSACTION ISOLATION LEVEL = SNAPSHOT,
	LANGUAGE = N'English'
)
	DECLARE @Counter int = 0;
	WHILE @Counter < 50000
	BEGIN
		INSERT InMemory.VehicleLocations(RegistrationNumber, TrackedWhen, Longitude, Latitude)
		VALUES(N'EA-232-JB', SYSDATETIME(), 125.4, 132.7);
		SET @Counter += 1;
	END;
	RETURN 0;
END;
GO
declare @start datetime2
set @start = SYSDATETIME()
EXECUTE InMemory.Insert50ThousandVehicleLocations
select datediff(ms,@start, sysdatetime()) as 'insert into memory-optimized table using native compilation (in ms)'
GO