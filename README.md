# CineReserva — Reservas de Cine, Transacciones y Modelo Estrella en SQL Server

Implementación de una base de datos híbrida (**OLTP + Modelo Estrella**) para la gestión de funciones, reserva y compra de entradas, control de disponibilidad de asientos y análisis de ingresos en **Microsoft SQL Server (T-SQL)**.

## Características principales
- **Arquitectura Híbrida (OLTP + Dimensional):**
  - **Tablas operativas:** `Cliente`, `Pelicula`, `Funcion`, `Entrada` y `Pago` con claves foráneas, unicidad y restricciones `CHECK` (`Precio > 0`, `AsientosDisponibles >= 0`, `Cantidad > 0`).
  - **Modelo Estrella (BI):** Tabla de hechos `FactEntrada` relacionada con `DimFecha`, `DimCanal`, `Cliente` y `Pelicula`.
- **Procedimientos Almacenados y Control Transaccional:**
  - `usp_FuncionesDisponibles`: consulta de funciones disponibles filtrada por cantidad mínima de asientos (`@Minimo`).
  - `usp_ReservarYComprar`: operación transaccional con `SET XACT_ABORT ON`, `BEGIN TRY...CATCH`, `ROLLBACK TRANSACTION` y parámetro `OUTPUT` (`@EntradaNueva`) para validar stock, descontar asientos, registrar entrada/pago y poblar `FactEntrada`.
- **Pruebas y Analítica Incluidas:**
  - Verificación de conteos iniciales por tabla mediante SQL dinámico.
  - Pruebas de compra exitosa (`@SimularFallo = 0`) y reversión total por fallo simulado (`@SimularFallo = 1`).
  - Consulta analítica de ingresos y asientos vendidos agrupados por película, género y canal.

## Contenido del repositorio
- `Codigo_SQL_CineReserva_14.sql`: Script completo ejecutable (creación de BD, tablas, datos iniciales, procedimientos almacenados, pruebas de integridad y consulta analítica).

## Cómo ejecutar
1. Abrir **SQL Server Management Studio (SSMS)** (SQL Server 2016 SP1 o superior).
2. Abrir y ejecutar `Codigo_SQL_CineReserva_14.sql` de principio a fin.