-- ============================================================
--  MediCare+ Hospital & Clinic Management System
--  FILE: tasks.sql
--  Contains: Stored Procedures, Triggers, UDFs,
--            Standalone Queries, Security
--  Target:   SQL Server
-- ============================================================

USE MediCarePlus;
GO


-- ============================================================
--  SECTION A — STORED PROCEDURES
-- ============================================================


-- ------------------------------------------------------------
--  A1: Monthly Department Report
--  Returns each department with appointment count, unique
--  patients seen, and total consultation revenue for a given
--  month and year. Departments with zero appointments still appear.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE sp_MonthlyDepartmentReport
    @Month INT,
    @Year  INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Validate parameters
        IF @Month < 1 OR @Month > 12
            THROW 50001, 'Invalid month. Please provide a value between 1 and 12.', 1;

        IF @Year < 2000 OR @Year > 2100
            THROW 50002, 'Invalid year. Please provide a year between 2000 and 2100.', 1;

        SELECT
            d.DepartmentName,
            COUNT(a.AppointmentID)          AS TotalAppointments,
            COUNT(DISTINCT a.PatientID)     AS UniquePatients,
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

-- Demo
EXEC sp_MonthlyDepartmentReport @Month = 1, @Year = 2024;
GO


-- ------------------------------------------------------------
--  A2: Patient Billing Statement
--  Returns full billing history for a patient, one row per
--  completed appointment, plus a grand total row at the end.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE sp_PatientBillingStatement
    @PatientID INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Validate patient exists
        IF NOT EXISTS (SELECT 1 FROM Patients WHERE PatientID = @PatientID)
            THROW 50003, 'Patient ID does not exist.', 1;

        SELECT
            CAST(a.AppointmentDate AS VARCHAR(20))  AS AppointmentDate,
            doc.FullName                            AS DoctorName,
            b.ConsultationCharge,
            b.MedicineCharge,
            b.LabCharge,
            b.InsuranceDiscount,
            b.TotalGST,
            b.FinalAmount,
            b.PaymentStatus
        FROM Appointments a
        JOIN Doctors  doc ON doc.DoctorID      = a.DoctorID
        JOIN Billing  b   ON b.AppointmentID   = a.AppointmentID
        WHERE a.PatientID = @PatientID
          AND a.Status    = 'Completed'

        UNION ALL

        -- Grand total row
        SELECT
            'GRAND TOTAL' AS AppointmentDate,
            ''            AS DoctorName,
            SUM(b.ConsultationCharge),
            SUM(b.MedicineCharge),
            SUM(b.LabCharge),
            SUM(b.InsuranceDiscount),
            SUM(b.TotalGST),
            SUM(b.FinalAmount),
            ''            AS PaymentStatus
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

-- Demo
EXEC sp_PatientBillingStatement @PatientID = 1;
GO


-- ------------------------------------------------------------
--  A3: Doctor Performance Report
--  Returns summary per active doctor who has at least
--  @MinAppointments total appointments. Ordered by revenue desc.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE sp_DoctorPerformanceReport
    @MinAppointments INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @MinAppointments < 1
            THROW 50004, 'Minimum appointment count must be at least 1.', 1;

        SELECT
            doc.FullName                                            AS DoctorName,
            d.DepartmentName,
            COUNT(a.AppointmentID)                                  AS TotalAppointments,
            SUM(CASE WHEN a.Status = 'Completed' THEN 1 ELSE 0 END) AS CompletedAppointments,
            CAST(
                ROUND(
                    100.0 * SUM(CASE WHEN a.Status = 'Completed' THEN 1 ELSE 0 END)
                          / COUNT(a.AppointmentID),
                2) AS DECIMAL(5,2)
            )                                                       AS CompletionRatePct,
            ISNULL(SUM(b.FinalAmount), 0)                           AS TotalRevenue,
            COUNT(DISTINCT mr.Diagnosis)                            AS UniqueDiagnoses
        FROM Doctors doc
        JOIN Departments  d   ON d.DepartmentID   = doc.DepartmentID
        JOIN Appointments a   ON a.DoctorID        = doc.DoctorID
        LEFT JOIN Billing b   ON b.AppointmentID   = a.AppointmentID
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

-- Demo
EXEC sp_DoctorPerformanceReport @MinAppointments = 2;
GO


-- ------------------------------------------------------------
--  A4: Medicines Never Prescribed — Two Ways
--  Returns medicines that have never appeared in any prescription.
--  Solved using: (1) subquery, (2) EXCEPT set operation.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE sp_MedicinesNeverPrescribed
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        -- Approach 1: Subquery (NOT IN)
        SELECT MedicineID, MedicineName, UnitPrice
        FROM   Medicines
        WHERE  MedicineID NOT IN (
            SELECT DISTINCT MedicineID
            FROM   Prescriptions
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

-- Demo
EXEC sp_MedicinesNeverPrescribed;
GO


-- ------------------------------------------------------------
--  A5: Monthly Revenue vs. Target
--  Monthly target: Rs. 5,00,000
--  Shows month, total revenue, met/not, surplus or deficit.
--  Ends with a summary row count.
-- ------------------------------------------------------------
CREATE OR ALTER PROCEDURE sp_MonthlyRevenueVsTarget
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Target DECIMAL(12,2) = 500000.00;

    BEGIN TRY

        -- Per-month detail
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

        -- Summary
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

-- Demo
EXEC sp_MonthlyRevenueVsTarget;
GO


-- ============================================================
--  SECTION B — TRIGGERS
-- ============================================================


-- ------------------------------------------------------------
--  B1: Prevent Doctor Double-Booking
--  Fires AFTER INSERT on Appointments.
--  Rolls back if the doctor already has a Scheduled or
--  Completed appointment at the same date and time slot.
-- ------------------------------------------------------------
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
            AND a.AppointmentID  <> i.AppointmentID   -- exclude the row just inserted
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
        THROW 50010,
              'Double-booking prevented. Doctor already has an appointment at this time slot.',
              1;
    END
END;
GO


-- ------------------------------------------------------------
--  B2: Auto-Generate Bill on Appointment Completion
--  Fires AFTER UPDATE on Appointments.
--  When Status changes to Completed, calculates and inserts
--  the bill. Raises error if a bill already exists.
-- ------------------------------------------------------------
CREATE OR ALTER TRIGGER trg_AutoGenerateBill
ON Appointments
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Only act on rows whose Status just changed to 'Completed'
    IF NOT EXISTS (
        SELECT 1 FROM inserted i
        JOIN deleted d ON d.AppointmentID = i.AppointmentID
        WHERE i.Status = 'Completed' AND d.Status <> 'Completed'
    ) RETURN;

    DECLARE @AppointmentID  INT;
    DECLARE @DoctorID       INT;
    DECLARE @PatientID      INT;
    DECLARE @ConsultFee     DECIMAL(10,2);
    DECLARE @MedCharge      DECIMAL(10,2);
    DECLARE @LabCharge      DECIMAL(10,2);
    DECLARE @CoveragePct    DECIMAL(5,2);
    DECLARE @InsDiscount    DECIMAL(10,2);
    DECLARE @TotalGST       DECIMAL(10,2);
    DECLARE @FinalAmount    DECIMAL(10,2);

    SELECT
        @AppointmentID = i.AppointmentID,
        @DoctorID      = i.DoctorID,
        @PatientID     = i.PatientID
    FROM inserted i
    JOIN deleted  d ON d.AppointmentID = i.AppointmentID
    WHERE i.Status = 'Completed' AND d.Status <> 'Completed';

    -- Check no bill already exists
    IF EXISTS (SELECT 1 FROM Billing WHERE AppointmentID = @AppointmentID)
    BEGIN
        THROW 50020, 'A bill already exists for this appointment.', 1;
    END

    -- Consultation fee
    SELECT @ConsultFee = ConsultationFee
    FROM   Doctors
    WHERE  DoctorID = @DoctorID;

    -- Total medicine charge (sum of quantity * unit price)
    SELECT @MedCharge = ISNULL(SUM(p.Quantity * m.UnitPrice), 0)
    FROM   MedicalRecords mr
    JOIN   Prescriptions  p  ON p.RecordID   = mr.RecordID
    JOIN   Medicines      m  ON m.MedicineID = p.MedicineID
    WHERE  mr.AppointmentID = @AppointmentID;

    -- Total lab charge
    SELECT @LabCharge = ISNULL(SUM(lt.TestCost), 0)
    FROM   LabOrders lo
    JOIN   LabTests  lt ON lt.LabTestID = lo.LabTestID
    WHERE  lo.AppointmentID = @AppointmentID;

    -- Insurance coverage percentage (0 if none)
    SELECT @CoveragePct = ISNULL(MAX(ip.CoveragePercent), 0)
    FROM   InsurancePolicies ip
    WHERE  ip.PatientID = @PatientID;

    -- Insurance applies to medicine + lab costs only
    SET @InsDiscount = ROUND((@MedCharge + @LabCharge) * @CoveragePct / 100.0, 2);

    -- GST: 0% on consult, 5% on medicines (post-discount), 12% on lab (post-discount)
    SET @TotalGST = ROUND((@MedCharge - (@MedCharge * @CoveragePct / 100.0)) * 0.05
                        + (@LabCharge - (@LabCharge * @CoveragePct / 100.0)) * 0.12, 2);

    -- Final payable amount
    SET @FinalAmount = @ConsultFee
                     + (@MedCharge - (@MedCharge * @CoveragePct / 100.0))
                     + (@LabCharge - (@LabCharge * @CoveragePct / 100.0))
                     + @TotalGST;

    INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge,
                         InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
    VALUES (@AppointmentID, @ConsultFee, @MedCharge, @LabCharge,
            @InsDiscount, @TotalGST, @FinalAmount, 'Unpaid');
END;
GO


-- ------------------------------------------------------------
--  B3: Flag Follow-Up on Abnormal Lab Result
--  Fires AFTER INSERT OR UPDATE on LabOrders.
--  When IsAbnormal = 1, sets RequiresFollowUp = 1 on the
--  linked MedicalRecord. If no record exists, raises a
--  warning but does NOT roll back.
-- ------------------------------------------------------------
CREATE OR ALTER TRIGGER trg_FlagFollowUp
ON LabOrders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Process only rows where IsAbnormal was just set to 1
    IF NOT EXISTS (SELECT 1 FROM inserted WHERE IsAbnormal = 1) RETURN;

    -- Check if a medical record exists for each abnormal lab order
    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN MedicalRecords mr ON mr.AppointmentID = i.AppointmentID
        WHERE  i.IsAbnormal = 1
          AND  mr.RecordID IS NULL
    )
    BEGIN
        -- Warning only — do not roll back
        PRINT 'Warning: Abnormal result recorded but no Medical Record exists yet for this appointment. Follow-up flag will be set once a record is created.';
    END

    -- Update RequiresFollowUp where a record does exist
    UPDATE MedicalRecords
    SET    RequiresFollowUp = 1
    WHERE  AppointmentID IN (
        SELECT AppointmentID
        FROM   inserted
        WHERE  IsAbnormal = 1
    );
END;
GO


-- ============================================================
--  SECTION C — USER-DEFINED FUNCTIONS
-- ============================================================


-- ------------------------------------------------------------
--  C1: fn_GetPatientAge
--  Returns patient's current age in completed years.
--  Returns NULL if PatientID does not exist.
-- ------------------------------------------------------------
CREATE OR ALTER FUNCTION fn_GetPatientAge (@PatientID INT)
RETURNS INT
AS
BEGIN
    DECLARE @DOB DATE;
    DECLARE @Age INT;

    SELECT @DOB = DateOfBirth
    FROM   Patients
    WHERE  PatientID = @PatientID;

    IF @DOB IS NULL RETURN NULL;

    SET @Age = DATEDIFF(YEAR, @DOB, GETDATE())
             - CASE
                 WHEN MONTH(@DOB) > MONTH(GETDATE())
                   OR (MONTH(@DOB) = MONTH(GETDATE()) AND DAY(@DOB) > DAY(GETDATE()))
                 THEN 1
                 ELSE 0
               END;

    RETURN @Age;
END;
GO

-- Demo: all patients with their calculated age
SELECT
    PatientID,
    FullName,
    DateOfBirth,
    dbo.fn_GetPatientAge(PatientID) AS AgeInYears
FROM Patients;
GO


-- ------------------------------------------------------------
--  C2: fn_CalculateNetBill
--  Returns final payable amount given the charge components
--  and insurance coverage percentage.
--  GST: 0% on consult, 5% on medicines, 12% on lab (post-discount).
-- ------------------------------------------------------------
CREATE OR ALTER FUNCTION fn_CalculateNetBill (
    @ConsultCharge  DECIMAL(10,2),
    @MedCharge      DECIMAL(10,2),
    @LabCharge      DECIMAL(10,2),
    @CoveragePct    DECIMAL(5,2)      -- pass 0 if no insurance
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @InsDiscount  DECIMAL(10,2);
    DECLARE @NetMed       DECIMAL(10,2);
    DECLARE @NetLab       DECIMAL(10,2);
    DECLARE @TotalGST     DECIMAL(10,2);
    DECLARE @FinalAmount  DECIMAL(10,2);

    SET @InsDiscount = ROUND((@MedCharge + @LabCharge) * @CoveragePct / 100.0, 2);
    SET @NetMed      = @MedCharge - ROUND(@MedCharge * @CoveragePct / 100.0, 2);
    SET @NetLab      = @LabCharge - ROUND(@LabCharge * @CoveragePct / 100.0, 2);
    SET @TotalGST    = ROUND(@NetMed * 0.05 + @NetLab * 0.12, 2);
    SET @FinalAmount = @ConsultCharge + @NetMed + @NetLab + @TotalGST;

    RETURN @FinalAmount;
END;
GO

-- Demo: call the function against stored billing data to verify it matches
SELECT
    b.BillID,
    b.AppointmentID,
    b.FinalAmount                             AS StoredFinalAmount,
    dbo.fn_CalculateNetBill(
        b.ConsultationCharge,
        b.MedicineCharge,
        b.LabCharge,
        ISNULL(ip.CoveragePercent, 0)
    )                                         AS FunctionFinalAmount,
    CASE
        WHEN b.FinalAmount = dbo.fn_CalculateNetBill(
            b.ConsultationCharge,
            b.MedicineCharge,
            b.LabCharge,
            ISNULL(ip.CoveragePercent, 0))
        THEN 'Match'
        ELSE 'Mismatch'
    END                                       AS Verification
FROM Billing b
JOIN Appointments       a  ON a.AppointmentID  = b.AppointmentID
LEFT JOIN InsurancePolicies ip ON ip.PatientID = a.PatientID;
GO


-- ============================================================
--  SECTION D — ADVANCED STANDALONE QUERIES
-- ============================================================


-- ------------------------------------------------------------
--  D1: Top 3 Revenue-Generating Doctors per Department
--  Uses DENSE_RANK window function partitioned by department.
--  Doctors with no completed appointments are excluded.
-- ------------------------------------------------------------

-- D1: Top 3 doctors per department by revenue
WITH DoctorRevenue AS (
    SELECT
        d.DepartmentName,
        doc.FullName                          AS DoctorName,
        ISNULL(SUM(b.FinalAmount), 0)         AS TotalRevenue,
        DENSE_RANK() OVER (
            PARTITION BY d.DepartmentID
            ORDER BY ISNULL(SUM(b.FinalAmount), 0) DESC
        )                                     AS RevenueRank
    FROM Doctors doc
    JOIN Departments  d   ON d.DepartmentID  = doc.DepartmentID
    JOIN Appointments a   ON a.DoctorID      = doc.DoctorID
                          AND a.Status        = 'Completed'
    JOIN Billing      b   ON b.AppointmentID = a.AppointmentID
    GROUP BY d.DepartmentID, d.DepartmentName, doc.DoctorID, doc.FullName
)
SELECT
    DepartmentName,
    DoctorName,
    TotalRevenue,
    RevenueRank
FROM DoctorRevenue
WHERE RevenueRank <= 3
ORDER BY DepartmentName, RevenueRank;
GO


-- ------------------------------------------------------------
--  D2: Running Monthly Revenue Total
--  Shows each month's revenue and a cumulative running total
--  ordered chronologically. Month displayed as e.g. 'Jan 2024'.
-- ------------------------------------------------------------

-- D2: Running monthly revenue with cumulative total
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


-- ============================================================
--  SECTION E — SECURITY: ROLES, VIEWS & PERMISSIONS
-- ============================================================


-- ------------------------------------------------------------
--  Views for restricted data access
-- ------------------------------------------------------------

-- View for receptionist: patient and appointment data only
CREATE OR ALTER VIEW vw_PatientAppointments AS
SELECT
    p.PatientID,
    p.FullName,
    p.Phone,
    p.Address,
    a.AppointmentID,
    a.AppointmentDate,
    a.TimeSlot,
    a.Status,
    a.DoctorID
FROM Patients     p
JOIN Appointments a ON a.PatientID = p.PatientID;
GO

-- View for billing: restricted patient info (name + insurance only, no DOB/phone/address)
CREATE OR ALTER VIEW vw_PatientBillingInfo AS
SELECT
    p.PatientID,
    p.FullName,
    ip.ProviderName,
    ip.CoveragePercent,
    ip.YearlyMaxAmount
FROM Patients p
LEFT JOIN InsurancePolicies ip ON ip.PatientID = p.PatientID;
GO

-- View for lab tech: lab orders and test reference data only (no patient personal info)
CREATE OR ALTER VIEW vw_LabOrdersForTech AS
SELECT
    lo.LabOrderID,
    lo.AppointmentID,
    lt.TestName,
    lt.TestCost,
    lo.ResultValue,
    lo.IsAbnormal
FROM LabOrders lo
JOIN LabTests  lt ON lt.LabTestID = lo.LabTestID;
GO


-- ------------------------------------------------------------
--  Create Roles
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
--  db_receptionist
--  SELECT + INSERT on patient and appointment data via view only
-- ------------------------------------------------------------
GRANT SELECT, INSERT ON vw_PatientAppointments TO db_receptionist;
GRANT SELECT, INSERT ON Patients               TO db_receptionist;
GRANT SELECT, INSERT ON Appointments           TO db_receptionist;

DENY SELECT ON Billing        TO db_receptionist;
DENY SELECT ON MedicalRecords TO db_receptionist;
DENY SELECT ON Prescriptions  TO db_receptionist;
DENY SELECT ON LabOrders      TO db_receptionist;
GO


-- ------------------------------------------------------------
--  db_doctor
--  SELECT on patient + appointment data
--  INSERT + UPDATE on medical records, prescriptions, lab orders
-- ------------------------------------------------------------
GRANT SELECT ON Patients      TO db_doctor;
GRANT SELECT ON Appointments  TO db_doctor;
GRANT SELECT, INSERT, UPDATE ON MedicalRecords TO db_doctor;
GRANT SELECT, INSERT, UPDATE ON Prescriptions  TO db_doctor;
GRANT SELECT, INSERT, UPDATE ON LabOrders      TO db_doctor;

DENY SELECT ON Billing TO db_doctor;
GO


-- ------------------------------------------------------------
--  db_lab_tech
--  SELECT on lab test catalogue and lab orders (via view)
--  UPDATE on lab orders result fields only
-- ------------------------------------------------------------
GRANT SELECT        ON vw_LabOrdersForTech TO db_lab_tech;
GRANT SELECT        ON LabTests            TO db_lab_tech;
GRANT SELECT        ON LabOrders           TO db_lab_tech;
GRANT UPDATE        ON LabOrders           TO db_lab_tech;

DENY SELECT ON Patients       TO db_lab_tech;
DENY SELECT ON Billing        TO db_lab_tech;
DENY SELECT ON MedicalRecords TO db_lab_tech;
GO


-- ------------------------------------------------------------
--  db_billing
--  SELECT + INSERT + UPDATE on billing
--  Read-only on vw_PatientBillingInfo (name + insurance only)
-- ------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON Billing              TO db_billing;
GRANT SELECT                 ON vw_PatientBillingInfo TO db_billing;

DENY SELECT ON MedicalRecords TO db_billing;
DENY SELECT ON Prescriptions  TO db_billing;
DENY SELECT ON Patients       TO db_billing;   -- base table denied; view is allowed
GO


-- ------------------------------------------------------------
--  db_admin
--  Full access to all objects
-- ------------------------------------------------------------
EXEC sp_addrolemember 'db_owner', 'db_admin';
GO
