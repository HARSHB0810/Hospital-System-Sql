
USE MediCarePlus;
GO


--  SECTION A — STORED PROCEDURES


-- A1: Monthly Department Report
CREATE OR ALTER PROCEDURE sp_MonthlyDepartmentReport
    @Month INT,
    @Year  INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @Month < 1 OR @Month > 12
            THROW 50001, 'Invalid month. Please provide a value between 1 and 12.', 1;

        IF @Year < 2000 OR @Year > 2100
            THROW 50002, 'Invalid year. Please provide a year between 2000 and 2100.', 1;

        SELECT
            d.DepartmentName,
            COUNT(a.AppointmentID)              AS TotalAppointments,
            COUNT(DISTINCT a.PatientID)         AS UniquePatients,
            ISNULL(SUM(doc.ConsultationFee), 0) AS TotalConsultationRevenue
        FROM Departments d
        LEFT JOIN Doctors doc
            ON doc.DepartmentID = d.DepartmentID
        LEFT JOIN Appointments a
            ON  a.DoctorID = doc.DoctorID
            AND MONTH(a.AppointmentDate) = @Month
            AND YEAR(a.AppointmentDate)  = @Year
            AND a.Status = 'Completed'
        GROUP BY d.DepartmentID, d.DepartmentName
        ORDER BY d.DepartmentName;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

EXEC sp_MonthlyDepartmentReport @Month = 1, @Year = 2024;
GO


-- A2: Patient Billing Statement
CREATE OR ALTER PROCEDURE sp_PatientBillingStatement
    @PatientID INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM Patients WHERE PatientID = @PatientID)
            THROW 50003, 'Patient ID does not exist.', 1;

        SELECT
            CAST(a.AppointmentDate AS VARCHAR(20)) AS AppointmentDate,
            doc.FullName                           AS DoctorName,
            b.ConsultationCharge,
            b.MedicineCharge,
            b.LabCharge,
            b.InsuranceDiscount,
            b.FinalAmount,
            b.PaymentStatus
        FROM Appointments a
        JOIN Doctors doc ON doc.DoctorID    = a.DoctorID
        JOIN Billing b   ON b.AppointmentID = a.AppointmentID
        WHERE a.PatientID = @PatientID
          AND a.Status    = 'Completed'

        UNION ALL

        SELECT
            'GRAND TOTAL',
            '',
            SUM(b.ConsultationCharge),
            SUM(b.MedicineCharge),
            SUM(b.LabCharge),
            SUM(b.InsuranceDiscount),
            SUM(b.FinalAmount),
            ''
        FROM Appointments a
        JOIN Billing b ON b.AppointmentID = a.AppointmentID
        WHERE a.PatientID = @PatientID
          AND a.Status    = 'Completed';
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

EXEC sp_PatientBillingStatement @PatientID = 1;
GO


-- A3: Doctor Performance Report
CREATE OR ALTER PROCEDURE sp_DoctorPerformanceReport
    @MinAppointments INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @MinAppointments < 1
            THROW 50004, 'Minimum appointment count must be at least 1.', 1;

        SELECT
            doc.FullName                                             AS DoctorName,
            d.DepartmentName,
            COUNT(a.AppointmentID)                                   AS TotalAppointments,
            SUM(CASE WHEN a.Status = 'Completed' THEN 1 ELSE 0 END) AS CompletedAppointments,
            CAST(
                ROUND(
                    100.0 * SUM(CASE WHEN a.Status = 'Completed' THEN 1 ELSE 0 END)
                          / COUNT(a.AppointmentID),
                2) AS DECIMAL(5,2)
            )                                                        AS CompletionRatePct,
            ISNULL(SUM(b.FinalAmount), 0)                            AS TotalRevenue,
            COUNT(DISTINCT mr.Diagnosis)                             AS UniqueDiagnoses
        FROM Doctors doc
        JOIN Departments     d  ON d.DepartmentID  = doc.DepartmentID
        JOIN Appointments    a  ON a.DoctorID       = doc.DoctorID
        LEFT JOIN Billing    b  ON b.AppointmentID  = a.AppointmentID
        LEFT JOIN MedicalRecords mr ON mr.AppointmentID = a.AppointmentID
        WHERE doc.IsActive = 1
        GROUP BY doc.DoctorID, doc.FullName, d.DepartmentName
        HAVING COUNT(a.AppointmentID) >= @MinAppointments
        ORDER BY TotalRevenue DESC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

EXEC sp_DoctorPerformanceReport @MinAppointments = 2;
GO


-- A4: Medicines Never Prescribed — Two Ways
CREATE OR ALTER PROCEDURE sp_MedicinesNeverPrescribed
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        -- Approach 1: Subquery (NOT IN)
        SELECT MedicineID, MedicineName, UnitPrice
        FROM   Medicines
        WHERE  MedicineID NOT IN (
            SELECT DISTINCT MedicineID FROM Prescriptions
        );

        -- Approach 2: SET operation (EXCEPT)
        SELECT MedicineID, MedicineName, UnitPrice
        FROM   Medicines
        EXCEPT
        SELECT m.MedicineID, m.MedicineName, m.UnitPrice
        FROM   Medicines m
        JOIN   Prescriptions p ON p.MedicineID = m.MedicineID;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

EXEC sp_MedicinesNeverPrescribed;
GO


-- A5: Monthly Revenue vs. Target
CREATE OR ALTER PROCEDURE sp_MonthlyRevenueVsTarget
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Target DECIMAL(12,2) = 500000.00;
    BEGIN TRY

        WITH MonthlyRevenue AS (
            SELECT
                YEAR(a.AppointmentDate)  AS RevenueYear,
                MONTH(a.AppointmentDate) AS RevenueMonth,
                SUM(b.FinalAmount)       AS TotalRevenue
            FROM Appointments a
            JOIN Billing b ON b.AppointmentID = a.AppointmentID
            WHERE a.Status = 'Completed'
            GROUP BY YEAR(a.AppointmentDate), MONTH(a.AppointmentDate)
        )
        SELECT
            FORMAT(DATEFROMPARTS(RevenueYear, RevenueMonth, 1), 'MMM yyyy') AS MonthYear,
            TotalRevenue,
            CASE WHEN TotalRevenue >= @Target THEN 'Yes' ELSE 'No' END       AS TargetMet,
            TotalRevenue - @Target                                            AS SurplusOrDeficit
        FROM MonthlyRevenue
        ORDER BY RevenueYear, RevenueMonth;

        WITH MonthlyRevenue AS (
            SELECT
                YEAR(a.AppointmentDate)  AS RevenueYear,
                MONTH(a.AppointmentDate) AS RevenueMonth,
                SUM(b.FinalAmount)       AS TotalRevenue
            FROM Appointments a
            JOIN Billing b ON b.AppointmentID = a.AppointmentID
            WHERE a.Status = 'Completed'
            GROUP BY YEAR(a.AppointmentDate), MONTH(a.AppointmentDate)
        )
        SELECT
            SUM(CASE WHEN TotalRevenue >= @Target THEN 1 ELSE 0 END) AS MonthsTargetMet,
            SUM(CASE WHEN TotalRevenue <  @Target THEN 1 ELSE 0 END) AS MonthsTargetMissed
        FROM MonthlyRevenue;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

EXEC sp_MonthlyRevenueVsTarget;
GO

--  SECTION B — TRIGGERS


-- B1: Prevent Doctor Double-Booking
CREATE OR ALTER TRIGGER trg_PreventDoubleBooking
ON Appointments
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM Appointments a
        JOIN inserted i
            ON  a.DoctorID        = i.DoctorID
            AND a.AppointmentDate = i.AppointmentDate
            AND a.TimeSlot        = i.TimeSlot
            AND a.Status          IN ('Scheduled', 'Completed')
            AND a.AppointmentID  <> i.AppointmentID
    )
    BEGIN
        DECLARE @DoctorName VARCHAR(150);
        DECLARE @Slot       VARCHAR(20);

        SELECT @DoctorName = d.FullName
        FROM   inserted i
        JOIN   Doctors  d ON d.DoctorID = i.DoctorID;

        SELECT @Slot = CAST(TimeSlot AS VARCHAR) + ' on ' + CAST(AppointmentDate AS VARCHAR)
        FROM   inserted;

        ROLLBACK TRANSACTION;
        THROW 50010, 'Double-booking prevented. Doctor already has an appointment at this time slot.', 1;
    END
END;
GO


-- B2: Auto-Generate Bill on Appointment Completion
CREATE OR ALTER TRIGGER trg_AutoGenerateBill
ON Appointments
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM inserted i
        JOIN deleted d ON d.AppointmentID = i.AppointmentID
        WHERE i.Status = 'Completed' AND d.Status <> 'Completed'
    ) RETURN;

    DECLARE @AppointmentID INT;
    DECLARE @DoctorID      INT;
    DECLARE @PatientID     INT;
    DECLARE @ConsultFee    DECIMAL(10,2);
    DECLARE @MedCharge     DECIMAL(10,2);
    DECLARE @LabCharge     DECIMAL(10,2);
    DECLARE @CoveragePct   DECIMAL(5,2);
    DECLARE @InsDiscount   DECIMAL(10,2);
    DECLARE @FinalAmount   DECIMAL(10,2);

    SELECT
        @AppointmentID = i.AppointmentID,
        @DoctorID      = i.DoctorID,
        @PatientID     = i.PatientID
    FROM inserted i
    JOIN deleted  d ON d.AppointmentID = i.AppointmentID
    WHERE i.Status = 'Completed' AND d.Status <> 'Completed';

    IF EXISTS (SELECT 1 FROM Billing WHERE AppointmentID = @AppointmentID)
        THROW 50020, 'A bill already exists for this appointment.', 1;

    SELECT @ConsultFee = ConsultationFee
    FROM   Doctors WHERE DoctorID = @DoctorID;

    SELECT @MedCharge = ISNULL(SUM(p.Quantity * m.UnitPrice), 0)
    FROM   MedicalRecords mr
    JOIN   Prescriptions  p ON p.RecordID   = mr.RecordID
    JOIN   Medicines      m ON m.MedicineID = p.MedicineID
    WHERE  mr.AppointmentID = @AppointmentID;

    SELECT @LabCharge = ISNULL(SUM(lt.TestCost), 0)
    FROM   LabOrders lo
    JOIN   LabTests  lt ON lt.LabTestID = lo.LabTestID
    WHERE  lo.AppointmentID = @AppointmentID;

    SELECT @CoveragePct = ISNULL(MAX(ip.CoveragePercent), 0)
    FROM   InsurancePolicies ip WHERE ip.PatientID = @PatientID;

    SET @InsDiscount = ROUND((@MedCharge + @LabCharge) * @CoveragePct / 100.0, 2);

    SET @FinalAmount = @ConsultFee
                     + (@MedCharge - ROUND(@MedCharge * @CoveragePct / 100.0, 2))
                     + (@LabCharge - ROUND(@LabCharge * @CoveragePct / 100.0, 2))
                     + ROUND((@MedCharge - ROUND(@MedCharge * @CoveragePct / 100.0, 2)) * 0.05
                           + (@LabCharge - ROUND(@LabCharge * @CoveragePct / 100.0, 2)) * 0.12, 2);

    INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge,
                         InsuranceDiscount, FinalAmount, PaymentStatus)
    VALUES (@AppointmentID, @ConsultFee, @MedCharge, @LabCharge,
            @InsDiscount, @FinalAmount, 'Unpaid');
END;
GO


-- B3: Flag Follow-Up on Abnormal Lab Result
CREATE OR ALTER TRIGGER trg_FlagFollowUp
ON LabOrders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted WHERE IsAbnormal = 1) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN MedicalRecords mr ON mr.AppointmentID = i.AppointmentID
        WHERE  i.IsAbnormal = 1 AND mr.RecordID IS NULL
    )
    BEGIN
        PRINT 'Warning: Abnormal result recorded but no Medical Record exists yet for this appointment.';
    END

    UPDATE MedicalRecords
    SET    RequiresFollowUp = 1
    WHERE  AppointmentID IN (
        SELECT AppointmentID FROM inserted WHERE IsAbnormal = 1
    );
END;
GO


--  SECTION C — USER-DEFINED FUNCTIONS


-- C1: Patient Age Calculator
CREATE OR ALTER FUNCTION fn_GetPatientAge (@PatientID INT)
RETURNS INT
AS
BEGIN
    DECLARE @DOB DATE;
    DECLARE @Age INT;

    SELECT @DOB = DateOfBirth FROM Patients WHERE PatientID = @PatientID;

    IF @DOB IS NULL RETURN NULL;

    SET @Age = DATEDIFF(YEAR, @DOB, GETDATE())
             - CASE
                 WHEN MONTH(@DOB) > MONTH(GETDATE())
                   OR (MONTH(@DOB) = MONTH(GETDATE()) AND DAY(@DOB) > DAY(GETDATE()))
                 THEN 1 ELSE 0
               END;
    RETURN @Age;
END;
GO

SELECT
    PatientID,
    FullName,
    DateOfBirth,
    dbo.fn_GetPatientAge(PatientID) AS AgeInYears
FROM Patients;
GO


-- C2: Net Bill Calculator
CREATE OR ALTER FUNCTION fn_CalculateNetBill (
    @ConsultCharge DECIMAL(10,2),
    @MedCharge     DECIMAL(10,2),
    @LabCharge     DECIMAL(10,2),
    @CoveragePct   DECIMAL(5,2)
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @InsDiscount DECIMAL(10,2);
    DECLARE @NetMed      DECIMAL(10,2);
    DECLARE @NetLab      DECIMAL(10,2);
    DECLARE @FinalAmount DECIMAL(10,2);

    SET @InsDiscount = ROUND((@MedCharge + @LabCharge) * @CoveragePct / 100.0, 2);
    SET @NetMed      = @MedCharge - ROUND(@MedCharge * @CoveragePct / 100.0, 2);
    SET @NetLab      = @LabCharge - ROUND(@LabCharge * @CoveragePct / 100.0, 2);
    SET @FinalAmount = @ConsultCharge + @NetMed + @NetLab
                     + ROUND(@NetMed * 0.05 + @NetLab * 0.12, 2);
    RETURN @FinalAmount;
END;
GO

SELECT
    b.BillID,
    b.AppointmentID,
    b.FinalAmount                          AS StoredFinalAmount,
    dbo.fn_CalculateNetBill(
        b.ConsultationCharge,
        b.MedicineCharge,
        b.LabCharge,
        ISNULL(ip.CoveragePercent, 0)
    )                                      AS FunctionFinalAmount,
    CASE
        WHEN b.FinalAmount = dbo.fn_CalculateNetBill(
            b.ConsultationCharge, b.MedicineCharge, b.LabCharge,
            ISNULL(ip.CoveragePercent, 0))
        THEN 'Match' ELSE 'Mismatch'
    END                                    AS Verification
FROM Billing b
JOIN Appointments        a  ON a.AppointmentID = b.AppointmentID
LEFT JOIN InsurancePolicies ip ON ip.PatientID = a.PatientID;
GO

--  SECTION D — ADVANCED STANDALONE QUERIES


-- D1: Top 3 Doctors per Department by Revenue
WITH DoctorRevenue AS (
    SELECT
        d.DepartmentName,
        doc.FullName                  AS DoctorName,
        ISNULL(SUM(b.FinalAmount), 0) AS TotalRevenue,
        DENSE_RANK() OVER (
            PARTITION BY d.DepartmentID
            ORDER BY ISNULL(SUM(b.FinalAmount), 0) DESC
        )                             AS RevenueRank
    FROM Doctors doc
    JOIN Departments  d  ON d.DepartmentID  = doc.DepartmentID
    JOIN Appointments a  ON a.DoctorID      = doc.DoctorID
                        AND a.Status         = 'Completed'
    JOIN Billing      b  ON b.AppointmentID = a.AppointmentID
    GROUP BY d.DepartmentID, d.DepartmentName, doc.DoctorID, doc.FullName
)
SELECT DepartmentName, DoctorName, TotalRevenue, RevenueRank
FROM   DoctorRevenue
WHERE  RevenueRank <= 3
ORDER BY DepartmentName, RevenueRank;
GO


-- D2: Running Monthly Revenue Total
WITH MonthlyTotals AS (
    SELECT
        YEAR(a.AppointmentDate)  AS RevenueYear,
        MONTH(a.AppointmentDate) AS RevenueMonth,
        SUM(b.FinalAmount)       AS MonthlyRevenue
    FROM Appointments a
    JOIN Billing b ON b.AppointmentID = a.AppointmentID
    WHERE a.Status = 'Completed'
    GROUP BY YEAR(a.AppointmentDate), MONTH(a.AppointmentDate)
)
SELECT
    FORMAT(DATEFROMPARTS(RevenueYear, RevenueMonth, 1), 'MMM yyyy') AS MonthYear,
    MonthlyRevenue,
    SUM(MonthlyRevenue) OVER (
        ORDER BY RevenueYear, RevenueMonth
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                                AS CumulativeRevenue
FROM MonthlyTotals
ORDER BY RevenueYear, RevenueMonth;
GO



--  SECTION E — SECURITY: ROLES, VIEWS & PERMISSIONS

CREATE OR ALTER VIEW vw_PatientAppointments AS
SELECT
    p.PatientID, p.FullName, p.Phone, p.Address,
    a.AppointmentID, a.AppointmentDate, a.TimeSlot, a.Status, a.DoctorID
FROM Patients     p
JOIN Appointments a ON a.PatientID = p.PatientID;
GO

CREATE OR ALTER VIEW vw_PatientBillingInfo AS
SELECT
    p.PatientID, p.FullName,
    ip.ProviderName, ip.CoveragePercent, ip.YearlyMaxAmount
FROM Patients p
LEFT JOIN InsurancePolicies ip ON ip.PatientID = p.PatientID;
GO

CREATE OR ALTER VIEW vw_LabOrdersForTech AS
SELECT
    lo.LabOrderID, lo.AppointmentID,
    lt.TestName, lt.TestCost,
    lo.ResultValue, lo.IsAbnormal
FROM LabOrders lo
JOIN LabTests  lt ON lt.LabTestID = lo.LabTestID;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'db_receptionist' AND type = 'R')
    CREATE ROLE db_receptionist;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'db_doctor' AND type = 'R')
    CREATE ROLE db_doctor;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'db_lab_tech' AND type = 'R')
    CREATE ROLE db_lab_tech;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'db_billing' AND type = 'R')
    CREATE ROLE db_billing;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'db_admin' AND type = 'R')
    CREATE ROLE db_admin;
GO

GRANT SELECT, INSERT ON vw_PatientAppointments TO db_receptionist;
GRANT SELECT, INSERT ON Patients               TO db_receptionist;
GRANT SELECT, INSERT ON Appointments           TO db_receptionist;
DENY  SELECT ON Billing        TO db_receptionist;
DENY  SELECT ON MedicalRecords TO db_receptionist;
DENY  SELECT ON Prescriptions  TO db_receptionist;
DENY  SELECT ON LabOrders      TO db_receptionist;
GO

GRANT SELECT ON Patients     TO db_doctor;
GRANT SELECT ON Appointments TO db_doctor;
GRANT SELECT, INSERT, UPDATE ON MedicalRecords TO db_doctor;
GRANT SELECT, INSERT, UPDATE ON Prescriptions  TO db_doctor;
GRANT SELECT, INSERT, UPDATE ON LabOrders      TO db_doctor;
DENY  SELECT ON Billing TO db_doctor;
GO

GRANT SELECT        ON vw_LabOrdersForTech TO db_lab_tech;
GRANT SELECT        ON LabTests            TO db_lab_tech;
GRANT SELECT        ON LabOrders           TO db_lab_tech;
GRANT UPDATE        ON LabOrders           TO db_lab_tech;
DENY  SELECT ON Patients       TO db_lab_tech;
DENY  SELECT ON Billing        TO db_lab_tech;
DENY  SELECT ON MedicalRecords TO db_lab_tech;
GO

GRANT SELECT, INSERT, UPDATE ON Billing               TO db_billing;
GRANT SELECT                 ON vw_PatientBillingInfo  TO db_billing;
DENY  SELECT ON MedicalRecords TO db_billing;
DENY  SELECT ON Prescriptions  TO db_billing;
DENY  SELECT ON Patients       TO db_billing;
GO

EXEC sp_addrolemember 'db_owner', 'db_admin';
GO
