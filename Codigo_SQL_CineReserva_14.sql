-- BASE 2: CINERESERVA. Ejecutar en SSMS, independiente de NexoShop.
IF DB_ID(N'CineReserva_S14') IS NULL EXEC('CREATE DATABASE CineReserva_S14');
GO
USE CineReserva_S14;
GO
DROP TABLE IF EXISTS dbo.FactEntrada;
DROP TABLE IF EXISTS dbo.DimFecha;
DROP TABLE IF EXISTS dbo.DimCanal;
DROP TABLE IF EXISTS dbo.Pago;
DROP TABLE IF EXISTS dbo.Entrada;
DROP TABLE IF EXISTS dbo.Funcion;
DROP TABLE IF EXISTS dbo.Pelicula;
DROP TABLE IF EXISTS dbo.Cliente;
GO
CREATE TABLE dbo.Cliente(ClienteID INT PRIMARY KEY, Nombre VARCHAR(80) NOT NULL, Ciudad VARCHAR(40) NOT NULL);
CREATE TABLE dbo.Pelicula(PeliculaID INT PRIMARY KEY, Titulo VARCHAR(80) NOT NULL, Genero VARCHAR(40) NOT NULL);
CREATE TABLE dbo.Funcion(FuncionID INT PRIMARY KEY, PeliculaID INT NOT NULL REFERENCES dbo.Pelicula(PeliculaID), Fecha DATETIME2 NOT NULL, Precio DECIMAL(10,2) NOT NULL CHECK(Precio>0), AsientosDisponibles INT NOT NULL CHECK(AsientosDisponibles>=0));
CREATE TABLE dbo.Entrada(EntradaID INT IDENTITY(1,1) PRIMARY KEY, ClienteID INT NOT NULL REFERENCES dbo.Cliente(ClienteID), FuncionID INT NOT NULL REFERENCES dbo.Funcion(FuncionID), Cantidad INT NOT NULL CHECK(Cantidad>0), Estado VARCHAR(20) NOT NULL CHECK(Estado IN('RESERVADA','PAGADA')));
CREATE TABLE dbo.Pago(PagoID INT IDENTITY(1,1) PRIMARY KEY, EntradaID INT NOT NULL UNIQUE REFERENCES dbo.Entrada(EntradaID), Monto DECIMAL(10,2) NOT NULL CHECK(Monto>0), Estado VARCHAR(15) NOT NULL CHECK(Estado IN('APROBADO','RECHAZADO')));
CREATE TABLE dbo.DimFecha(FechaKey INT PRIMARY KEY, Fecha DATE NOT NULL UNIQUE, Anio SMALLINT NOT NULL, Mes TINYINT NOT NULL);
CREATE TABLE dbo.DimCanal(CanalID INT PRIMARY KEY, Canal VARCHAR(30) NOT NULL);
CREATE TABLE dbo.FactEntrada(FactID INT IDENTITY(1,1) PRIMARY KEY, EntradaID INT NOT NULL UNIQUE REFERENCES dbo.Entrada(EntradaID), ClienteID INT NOT NULL REFERENCES dbo.Cliente(ClienteID), PeliculaID INT NOT NULL REFERENCES dbo.Pelicula(PeliculaID), FechaKey INT NOT NULL REFERENCES dbo.DimFecha(FechaKey), CanalID INT NOT NULL REFERENCES dbo.DimCanal(CanalID), Cantidad INT NOT NULL CHECK(Cantidad>0), Importe DECIMAL(10,2) NOT NULL CHECK(Importe>0));
INSERT dbo.Cliente VALUES(1,'Sofía Pérez','Lima'),(2,'Diego Ruiz','Lima'),(3,'Elena Soto','Cusco');
INSERT dbo.Pelicula VALUES(10,'Misión Andina','Acción'),(11,'La Última Estrella','Ciencia ficción');
INSERT dbo.Funcion VALUES(201,10,'2026-11-14T18:00:00',25,5),(202,11,'2026-11-15T20:00:00',30,2);
INSERT dbo.DimFecha VALUES(20261114,'20261114',2026,11),(20261115,'20261115',2026,11);
INSERT dbo.DimCanal VALUES(1,'Web'),(2,'Taquilla');
SELECT 'Cliente' Tabla,COUNT(*) Total FROM dbo.Cliente UNION ALL SELECT 'Función',COUNT(*) FROM dbo.Funcion UNION ALL SELECT 'Entrada',COUNT(*) FROM dbo.Entrada;
-- Diagrama: Database Diagrams > New Database Diagram > agregar las 8 tablas.




---ACTIVIDAD INICIAL: VERIFICACIÓN DE TABLAS Y CONTEOS INICIALES

USE CineReserva_S14;
GO

DECLARE @sql NVARCHAR(MAX) = N'';
DECLARE @totalTablas INT;

SELECT @totalTablas = COUNT(*) FROM sys.tables;

SELECT @sql = @sql + STUFF((
    SELECT ' UNION ALL SELECT ''' + t.name + ''' AS Tabla, COUNT(*) AS TotalFilas FROM dbo.' + QUOTENAME(t.name)
    FROM sys.tables t
    FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 11, '');

EXEC sp_executesql @sql;
SELECT @totalTablas AS NumeroTotalDeTablas;
GO

---RETO A: PROCEDIMIENTO DE CONSULTA (dbo.usp_FuncionesDisponibles)
CREATE OR ALTER PROCEDURE dbo.usp_FuncionesDisponibles
    @Minimo INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        f.FuncionID,
        p.Titulo AS Pelicula,
        p.Genero,
        f.Fecha,
        f.Precio,
        f.AsientosDisponibles
    FROM dbo.Funcion f
    INNER JOIN dbo.Pelicula p ON f.PeliculaID = p.PeliculaID
    WHERE f.AsientosDisponibles >= @Minimo
    ORDER BY f.Fecha;
END;
GO

-- Pruebas del Reto A
EXEC dbo.usp_FuncionesDisponibles;
EXEC dbo.usp_FuncionesDisponibles @Minimo = 3;
GO




---RETO B: PROCEDIMIENTO TRANSACCIONAL SEGURO (dbo.usp_ReservarYComprar)

USE CineReserva_S14;
GO


CREATE OR ALTER PROCEDURE dbo.usp_ReservarYComprar
    @ClienteID INT,
    @FuncionID INT,
    @Cantidad INT,
    @CanalID INT = 1,
    @SimularFallo BIT = 0,
    @EntradaNueva INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @PeliculaID INT;
    DECLARE @FechaFuncion DATETIME2;
    DECLARE @FechaKey INT;
    DECLARE @PrecioUnitario DECIMAL(10,2);
    DECLARE @AsientosActuales INT;
    DECLARE @ImporteTotal DECIMAL(10,2);

    -- 1. Validaciones previas
    IF @Cantidad <= 0
        THROW 50001, 'Cantidad de asientos inválida. Debe ser mayor a 0.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Cliente WHERE ClienteID = @ClienteID)
        THROW 50002, 'Cliente inexistente.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.DimCanal WHERE CanalID = @CanalID)
        THROW 50003, 'Canal de venta inexistente.', 1;

    SELECT 
        @PeliculaID = PeliculaID,
        @FechaFuncion = Fecha,
        @PrecioUnitario = Precio,
        @AsientosActuales = AsientosDisponibles
    FROM dbo.Funcion
    WHERE FuncionID = @FuncionID;

    IF @PrecioUnitario IS NULL
        THROW 50004, 'Función inexistente.', 1;

    IF @AsientosActuales < @Cantidad
        THROW 50005, 'Asientos insuficientes para la función seleccionada.', 1;

    -- Obtener FechaKey en formato YYYYMMDD a partir de la fecha de la función
    SET @FechaKey = CONVERT(INT, FORMAT(@FechaFuncion, 'yyyyMMdd'));

    IF NOT EXISTS (SELECT 1 FROM dbo.DimFecha WHERE FechaKey = @FechaKey)
        THROW 50006, 'La fecha de la función no está registrada en DimFecha.', 1;

    SET @ImporteTotal = @PrecioUnitario * @Cantidad;

    -- 2. Bloque transaccional protegido
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Descontar asientos disponibles
        UPDATE dbo.Funcion
        SET AsientosDisponibles = AsientosDisponibles - @Cantidad
        WHERE FuncionID = @FuncionID
          AND AsientosDisponibles >= @Cantidad;

        IF @@ROWCOUNT = 0
            THROW 50007, 'Conflicto de concurrencia: asientos agotados durante la operación.', 1;

        -- Registrar Entrada pagada
        INSERT INTO dbo.Entrada (ClienteID, FuncionID, Cantidad, Estado)
        VALUES (@ClienteID, @FuncionID, @Cantidad, 'PAGADA');

        SET @EntradaNueva = CONVERT(INT, SCOPE_IDENTITY());

        -- Registrar Pago aprobado
        INSERT INTO dbo.Pago (EntradaID, Monto, Estado)
        VALUES (@EntradaNueva, @ImporteTotal, 'APROBADO');

        -- Simulación de fallo antes de confirmar (para pruebas de ROLLBACK)
        IF @SimularFallo = 1
            THROW 50099, 'Fallo simulado en pasarela de pago antes del COMMIT.', 1;

        -- Registrar en tabla de hechos (FactEntrada)
        INSERT INTO dbo.FactEntrada (EntradaID, ClienteID, PeliculaID, FechaKey, CanalID, Cantidad, Importe)
        VALUES (@EntradaNueva, @ClienteID, @PeliculaID, @FechaKey, @CanalID, @Cantidad, @ImporteTotal);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @EntradaNueva = NULL;
        THROW;
    END CATCH;
END;
GO





---RETO C: PRUEBAS DE INTEGRIDAD (COMPRA EXITOSA Y PAGO RECHAZADO)
USE CineReserva_S14;
GO

-- 0. Estado inicial de asientos antes de las pruebas (Función 201 = 5 asientos, Función 202 = 2 asientos)
SELECT FuncionID, PeliculaID, Fecha, Precio, AsientosDisponibles 
FROM dbo.Funcion;
GO

-- PRUEBA 1: Compra exitosa de 2 asientos de la Función 201 (ClienteID = 1, Canal = 1 Web)
DECLARE @EntradaGenerada INT;

EXEC dbo.usp_ReservarYComprar
    @ClienteID = 1,
    @FuncionID = 201,
    @Cantidad = 2,
    @CanalID = 1,
    @SimularFallo = 0,
    @EntradaNueva = @EntradaGenerada OUTPUT;

SELECT @EntradaGenerada AS EntradaGenerada_Exito;

-- Verificar estado tras compra exitosa (Función 201 debe bajar de 5 a 3 asientos; 1 registro en Entrada, Pago y FactEntrada)
SELECT FuncionID, AsientosDisponibles FROM dbo.Funcion WHERE FuncionID = 201;
SELECT * FROM dbo.Entrada;
SELECT * FROM dbo.Pago;
SELECT * FROM dbo.FactEntrada;
GO

-- PRUEBA 2: Pago rechazado / fallo simulado en la Función 202 (@SimularFallo = 1)
BEGIN TRY
    DECLARE @EntradaFallida INT;
    EXEC dbo.usp_ReservarYComprar
        @ClienteID = 2,
        @FuncionID = 202,
        @Cantidad = 1,
        @CanalID = 2,
        @SimularFallo = 1,
        @EntradaNueva = @EntradaFallida OUTPUT;
END TRY
BEGIN CATCH
    SELECT 
        ERROR_NUMBER() AS ErrorSimulado, 
        ERROR_MESSAGE() AS MensajeError;
END CATCH;

-- Verificar estado después del fallo: Función 202 sigue con 2 asientos y NO aumentaron los conteos
SELECT FuncionID, AsientosDisponibles FROM dbo.Funcion WHERE FuncionID = 202;
SELECT COUNT(*) AS TotalEntradas FROM dbo.Entrada;
SELECT COUNT(*) AS TotalPagos FROM dbo.Pago;
SELECT COUNT(*) AS TotalFactEntrada FROM dbo.FactEntrada;
GO




---RETO D: CONSULTA ANALÍTICA DE INGRESOS (ESQUEMA ESTRELLA)
USE CineReserva_S14;
GO

SELECT 
    p.Titulo AS Pelicula,
    p.Genero,
    c.Canal,
    COUNT(*) AS EntradasVendidas_Operaciones,
    SUM(f.Cantidad) AS TotalAsientos,
    SUM(f.Importe) AS IngresosTotales
FROM dbo.FactEntrada f
INNER JOIN dbo.Pelicula p ON f.PeliculaID = p.PeliculaID
INNER JOIN dbo.DimCanal c ON f.CanalID = c.CanalID
GROUP BY p.Titulo, p.Genero, c.Canal
ORDER BY IngresosTotales DESC;
GO

