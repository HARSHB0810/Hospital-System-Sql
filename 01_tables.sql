-- ============================================================
--  MediCare+ Hospital & Clinic Management System
--  FILE: tables.sql
--  Contains: CREATE TABLE statements + INSERT sample data
--  Target:   SQL Server
-- ============================================================

USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'MediCarePlus')
    DROP DATABASE MediCarePlus;
GO

CREATE DATABASE MediCarePlus;
GO

USE MediCarePlus;
GO

-- ============================================================
--  SECTION 1 — TABLE CREATION
-- ============================================================

-- ------------------------------------------------------------
--  TABLE 1: Departments
--  HeadDoctorID is nullable here; FK added after Doctors exist
-- ------------------------------------------------------------
CREATE TABLE Departments (
    DepartmentID   INT          IDENTITY(1,1) PRIMARY KEY,
    DepartmentName VARCHAR(100) NOT NULL UNIQUE,
    HeadDoctorID   INT          NULL
);
GO

-- ------------------------------------------------------------
--  TABLE 2: Doctors
-- ------------------------------------------------------------
CREATE TABLE Doctors (
    DoctorID        INT           IDENTITY(1,1) PRIMARY KEY,
    FullName        VARCHAR(150)  NOT NULL,
    DepartmentID    INT           NOT NULL,
    Specialisation  VARCHAR(100)  NULL,
    ConsultationFee DECIMAL(10,2) NOT NULL CHECK (ConsultationFee > 0),
    IsActive        BIT           NOT NULL DEFAULT 1,
    FOREIGN KEY (DepartmentID) REFERENCES Departments(DepartmentID)
);
GO

-- ------------------------------------------------------------
--  TABLE 3: DoctorSchedule
-- ------------------------------------------------------------
CREATE TABLE DoctorSchedule (
    ScheduleID INT         IDENTITY(1,1) PRIMARY KEY,
    DoctorID   INT         NOT NULL,
    DayOfWeek  VARCHAR(10) NOT NULL CHECK (DayOfWeek IN (
                   'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')),
    StartTime  TIME        NOT NULL,
    EndTime    TIME        NOT NULL,
    CONSTRAINT UQ_DoctorSchedule UNIQUE (DoctorID, DayOfWeek, StartTime),
    FOREIGN KEY (DoctorID) REFERENCES Doctors(DoctorID)
);
GO

-- ------------------------------------------------------------
--  TABLE 4: Patients
-- ------------------------------------------------------------
CREATE TABLE Patients (
    PatientID   INT          IDENTITY(1,1) PRIMARY KEY,
    FullName    VARCHAR(150) NOT NULL,
    DateOfBirth DATE         NOT NULL,
    Phone       VARCHAR(20)  NULL,
    Address     VARCHAR(300) NULL
);
GO

-- ------------------------------------------------------------
--  TABLE 5: InsurancePolicies
-- ------------------------------------------------------------
CREATE TABLE InsurancePolicies (
    PolicyID        INT           IDENTITY(1,1) PRIMARY KEY,
    PatientID       INT           NOT NULL,
    ProviderName    VARCHAR(150)  NOT NULL,
    CoveragePercent DECIMAL(5,2)  NOT NULL CHECK (CoveragePercent BETWEEN 0 AND 100),
    YearlyMaxAmount DECIMAL(12,2) NOT NULL CHECK (YearlyMaxAmount > 0),
    FOREIGN KEY (PatientID) REFERENCES Patients(PatientID)
);
GO

-- ------------------------------------------------------------
--  TABLE 6: Appointments
--  UNIQUE on (DoctorID, AppointmentDate, TimeSlot) prevents double-booking
-- ------------------------------------------------------------
CREATE TABLE Appointments (
    AppointmentID   INT         IDENTITY(1,1) PRIMARY KEY,
    PatientID       INT         NOT NULL,
    DoctorID        INT         NOT NULL,
    AppointmentDate DATE        NOT NULL,
    TimeSlot        TIME        NOT NULL,
    Status          VARCHAR(15) NOT NULL DEFAULT 'Scheduled'
                                CHECK (Status IN ('Scheduled','Completed','Cancelled')),
    CONSTRAINT UQ_DoctorSlot UNIQUE (DoctorID, AppointmentDate, TimeSlot),
    FOREIGN KEY (PatientID) REFERENCES Patients(PatientID),
    FOREIGN KEY (DoctorID)  REFERENCES Doctors(DoctorID)
);
GO

-- ------------------------------------------------------------
--  TABLE 7: MedicalRecords
--  UNIQUE on AppointmentID enforces the 1:1 relationship
-- ------------------------------------------------------------
CREATE TABLE MedicalRecords (
    RecordID         INT           IDENTITY(1,1) PRIMARY KEY,
    AppointmentID    INT           NOT NULL UNIQUE,
    Diagnosis        VARCHAR(500)  NOT NULL,
    TreatmentPlan    VARCHAR(1000) NULL,
    RequiresFollowUp BIT           NOT NULL DEFAULT 0,
    FOREIGN KEY (AppointmentID) REFERENCES Appointments(AppointmentID)
);
GO

-- ------------------------------------------------------------
--  TABLE 8: Medicines
-- ------------------------------------------------------------
CREATE TABLE Medicines (
    MedicineID   INT           IDENTITY(1,1) PRIMARY KEY,
    MedicineName VARCHAR(150)  NOT NULL UNIQUE,
    UnitPrice    DECIMAL(10,2) NOT NULL CHECK (UnitPrice > 0)
);
GO

-- ------------------------------------------------------------
--  TABLE 9: Prescriptions
-- ------------------------------------------------------------
CREATE TABLE Prescriptions (
    PrescriptionID INT           IDENTITY(1,1) PRIMARY KEY,
    RecordID       INT           NOT NULL,
    MedicineID     INT           NOT NULL,
    Dosage         VARCHAR(50)   NULL,
    DurationDays   INT           NULL CHECK (DurationDays > 0),
    Quantity       INT           NOT NULL CHECK (Quantity > 0),
    FOREIGN KEY (RecordID)   REFERENCES MedicalRecords(RecordID),
    FOREIGN KEY (MedicineID) REFERENCES Medicines(MedicineID)
);
GO

-- ------------------------------------------------------------
--  TABLE 10: LabTests  (catalogue / reference table)
-- ------------------------------------------------------------
CREATE TABLE LabTests (
    LabTestID INT           IDENTITY(1,1) PRIMARY KEY,
    TestName  VARCHAR(150)  NOT NULL UNIQUE,
    TestCost  DECIMAL(10,2) NOT NULL CHECK (TestCost > 0)
);
GO

-- ------------------------------------------------------------
--  TABLE 11: LabOrders
--  IsAbnormal is NULL until a result is recorded
-- ------------------------------------------------------------
CREATE TABLE LabOrders (
    LabOrderID    INT          IDENTITY(1,1) PRIMARY KEY,
    AppointmentID INT          NOT NULL,
    LabTestID     INT          NOT NULL,
    ResultValue   VARCHAR(200) NULL,
    IsAbnormal    BIT          NULL,
    FOREIGN KEY (AppointmentID) REFERENCES Appointments(AppointmentID),
    FOREIGN KEY (LabTestID)     REFERENCES LabTests(LabTestID)
);
GO

-- ------------------------------------------------------------
--  TABLE 12: Billing
--  UNIQUE on AppointmentID enforces the 1:1 relationship
--  GST stored as a single computed total (0% consult, 5% med, 12% lab)
-- ------------------------------------------------------------
CREATE TABLE Billing (
    BillID             INT           IDENTITY(1,1) PRIMARY KEY,
    AppointmentID      INT           NOT NULL UNIQUE,
    ConsultationCharge DECIMAL(10,2) NOT NULL DEFAULT 0,
    MedicineCharge     DECIMAL(10,2) NOT NULL DEFAULT 0,
    LabCharge          DECIMAL(10,2) NOT NULL DEFAULT 0,
    InsuranceDiscount  DECIMAL(10,2) NOT NULL DEFAULT 0,
    TotalGST           DECIMAL(10,2) NOT NULL DEFAULT 0,
    FinalAmount        DECIMAL(10,2) NOT NULL DEFAULT 0,
    PaymentStatus      VARCHAR(10)   NOT NULL DEFAULT 'Unpaid'
                                     CHECK (PaymentStatus IN ('Unpaid','Paid','Partial')),
    FOREIGN KEY (AppointmentID) REFERENCES Appointments(AppointmentID)
);
GO

-- ------------------------------------------------------------
--  Add FK: Departments.HeadDoctorID -> Doctors
--  Done after both tables exist to avoid circular dependency on creation
-- ------------------------------------------------------------
ALTER TABLE Departments
    ADD CONSTRAINT FK_Dept_HeadDoctor
    FOREIGN KEY (HeadDoctorID) REFERENCES Doctors(DoctorID);
GO


-- ============================================================
--  SECTION 2 — SAMPLE DATA
-- ============================================================

-- ------------------------------------------------------------
--  Departments  (HeadDoctorID set NULL first, updated below)
-- ------------------------------------------------------------
INSERT INTO Departments (DepartmentName, HeadDoctorID) VALUES
    ('Cardiology',       NULL),
    ('Orthopaedics',     NULL),
    ('Pathology',        NULL),
    ('Neurology',        NULL),
    ('General Medicine', NULL);
GO

-- ------------------------------------------------------------
--  Doctors
-- ------------------------------------------------------------
INSERT INTO Doctors (FullName, DepartmentID, Specialisation, ConsultationFee, IsActive) VALUES
    ('Dr. Arjun Mehta',   1, 'Interventional Cardiology', 1500.00, 1),
    ('Dr. Priya Sharma',  2, 'Joint Replacement',         1200.00, 1),
    ('Dr. Ravi Nair',     3, 'Clinical Pathology',         800.00, 1),
    ('Dr. Sunita Kapoor', 4, 'Stroke and Epilepsy',       1400.00, 1),
    ('Dr. Imran Sheikh',  5, 'Family Medicine',             700.00, 1);
GO

-- Update HeadDoctorID now that Doctors are inserted
UPDATE Departments SET HeadDoctorID = 1 WHERE DepartmentID = 1;
UPDATE Departments SET HeadDoctorID = 2 WHERE DepartmentID = 2;
UPDATE Departments SET HeadDoctorID = 3 WHERE DepartmentID = 3;
UPDATE Departments SET HeadDoctorID = 4 WHERE DepartmentID = 4;
UPDATE Departments SET HeadDoctorID = 5 WHERE DepartmentID = 5;
GO

-- ------------------------------------------------------------
--  DoctorSchedule
-- ------------------------------------------------------------
INSERT INTO DoctorSchedule (DoctorID, DayOfWeek, StartTime, EndTime) VALUES
    (1, 'Monday',    '09:00', '13:00'),
    (2, 'Tuesday',   '10:00', '14:00'),
    (3, 'Wednesday', '08:00', '12:00'),
    (4, 'Thursday',  '11:00', '15:00'),
    (5, 'Friday',    '09:00', '13:00');
GO

-- ------------------------------------------------------------
--  Patients
-- ------------------------------------------------------------
INSERT INTO Patients (FullName, DateOfBirth, Phone, Address) VALUES
    ('Rahul Verma',   '1990-03-15', '9876543210', '12 MG Road, Mumbai'),
    ('Anjali Singh',  '1985-07-22', '9123456780', '45 Park Street, Delhi'),
    ('Mohan Das',     '1975-11-08', '9988776655', '7 Lake View, Chennai'),
    ('Fatima Bano',   '2000-01-30', '9871234560', '23 Civil Lines, Jaipur'),
    ('Suresh Pillai', '1968-05-19', '9765432100', '9 Residency Road, Bangalore');
GO

-- ------------------------------------------------------------
--  InsurancePolicies  (3 of 5 patients have insurance)
-- ------------------------------------------------------------
INSERT INTO InsurancePolicies (PatientID, ProviderName, CoveragePercent, YearlyMaxAmount) VALUES
    (1, 'Star Health Insurance', 40.00, 50000.00),
    (2, 'HDFC ERGO Health',      50.00, 80000.00),
    (4, 'New India Assurance',   30.00, 40000.00);
GO

-- ------------------------------------------------------------
--  Medicines
-- ------------------------------------------------------------
INSERT INTO Medicines (MedicineName, UnitPrice) VALUES
    ('Amlodipine 5mg',    15.00),
    ('Ibuprofen 400mg',   10.00),
    ('Paracetamol 500mg',  5.00),
    ('Atorvastatin 10mg', 20.00),
    ('Metformin 500mg',   12.00);
GO

-- ------------------------------------------------------------
--  LabTests
-- ------------------------------------------------------------
INSERT INTO LabTests (TestName, TestCost) VALUES
    ('Complete Blood Count',  350.00),
    ('Lipid Profile',         600.00),
    ('Blood Glucose Fasting', 150.00),
    ('ECG',                   500.00),
    ('X-Ray Knee',            800.00);
GO

-- ------------------------------------------------------------
--  Appointments  (spread across Jan–May 2024)
-- ------------------------------------------------------------
INSERT INTO Appointments (PatientID, DoctorID, AppointmentDate, TimeSlot, Status) VALUES
    (1, 1, '2024-01-10', '09:00', 'Completed'),   -- ID 1
    (2, 2, '2024-01-15', '10:00', 'Completed'),   -- ID 2
    (3, 3, '2024-02-05', '08:00', 'Completed'),   -- ID 3
    (4, 4, '2024-02-20', '11:00', 'Cancelled'),   -- ID 4
    (5, 5, '2024-03-12', '09:00', 'Completed'),   -- ID 5
    (1, 2, '2024-03-18', '10:00', 'Completed'),   -- ID 6
    (2, 1, '2024-04-07', '09:00', 'Completed'),   -- ID 7
    (3, 5, '2024-04-14', '09:00', 'Scheduled'),   -- ID 8
    (4, 3, '2024-05-02', '08:00', 'Completed'),   -- ID 9
    (5, 4, '2024-05-20', '11:00', 'Completed');   -- ID 10
GO

-- ------------------------------------------------------------
--  MedicalRecords  (only for Completed appointments)
-- ------------------------------------------------------------
INSERT INTO MedicalRecords (AppointmentID, Diagnosis, TreatmentPlan, RequiresFollowUp) VALUES
    (1,  'Hypertension Stage 2',  'Medication and lifestyle changes',     0),
    (2,  'Knee Osteoarthritis',   'Physiotherapy and pain management',    0),
    (3,  'Anaemia',               'Iron supplements and diet correction', 0),
    (5,  'Viral Fever',           'Rest, fluids, and antipyretics',       0),
    (6,  'Ligament Strain',       'Rest, ice pack, and NSAIDs',           0),
    (7,  'Hyperlipidaemia',       'Statins and dietary changes',          0),
    (9,  'Diabetes Type 2',       'Metformin and glucose monitoring',     0),
    (10, 'Migraine',              'Analgesics and trigger avoidance',     0);
GO

-- ------------------------------------------------------------
--  Prescriptions
-- ------------------------------------------------------------
INSERT INTO Prescriptions (RecordID, MedicineID, Dosage, DurationDays, Quantity) VALUES
    (1, 1, '1 tablet once daily',   30, 30),   -- Amlodipine     — Hypertension
    (1, 4, '1 tablet once daily',   30, 30),   -- Atorvastatin   — Hypertension
    (2, 2, '1 tablet twice daily',  14, 28),   -- Ibuprofen      — Knee
    (3, 3, '1 tablet thrice daily',  7, 21),   -- Paracetamol    — Anaemia
    (5, 3, '1 tablet thrice daily',  5, 15),   -- Paracetamol    — Viral Fever
    (6, 2, '1 tablet twice daily',  10, 20),   -- Ibuprofen      — Ligament
    (7, 4, '1 tablet once daily',   60, 60),   -- Atorvastatin   — Hyperlipidaemia
    (8, 5, '1 tablet twice daily',  90, 180);  -- Metformin      — Diabetes
GO

-- ------------------------------------------------------------
--  LabOrders
-- ------------------------------------------------------------
INSERT INTO LabOrders (AppointmentID, LabTestID, ResultValue, IsAbnormal) VALUES
    (1,  4, 'Normal Sinus Rhythm',   0),   -- ECG
    (1,  2, 'LDL: 180 mg/dL',       1),   -- Lipid Profile — abnormal
    (2,  5, 'Mild joint space loss', 0),   -- X-Ray Knee
    (3,  1, 'Hb: 9.2 g/dL',         1),   -- CBC — abnormal (anaemia)
    (5,  1, 'WBC: 11,000',           1),   -- CBC — abnormal (infection)
    (7,  2, 'LDL: 210 mg/dL',        1),   -- Lipid Profile — abnormal
    (9,  3, 'FBS: 210 mg/dL',        1),   -- Glucose — abnormal
    (10, 1, 'All values normal',     0);   -- CBC — normal
GO

-- Reflect abnormal lab results in MedicalRecords
UPDATE MedicalRecords
SET    RequiresFollowUp = 1
WHERE  AppointmentID IN (
    SELECT DISTINCT AppointmentID
    FROM   LabOrders
    WHERE  IsAbnormal = 1
);
GO

-- ------------------------------------------------------------
--  Billing  (only for Completed appointments)
--
--  GST Rules:
--    Consultation : 0%
--    Medicines    : 5%  (applied after insurance discount)
--    Lab Tests    : 12% (applied after insurance discount)
--
--  Insurance discount applies to MedicineCharge + LabCharge only
-- ------------------------------------------------------------

-- Appt 1 | Patient 1 | 40% insurance
-- Med: (30*15)+(30*20) = 1050 | Lab: 500+600 = 1100
-- Discount: (1050+1100)*0.40 = 860
-- GST: (1050-420)*0.05 + (1100-440)*0.12 = 31.50+79.20 = 110.70
-- Final: 1500 + (1050-420) + (1100-440) + 110.70 = 2900.70
INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge, InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
VALUES (1, 1500.00, 1050.00, 1100.00, 860.00, 110.70, 2900.70, 'Paid');

-- Appt 2 | Patient 2 | 50% insurance
-- Med: 28*10 = 280 | Lab: 800
-- Discount: (280+800)*0.50 = 540
-- GST: (280-140)*0.05 + (800-400)*0.12 = 7.00+48.00 = 55.00
-- Final: 1200+140+400+55 = 1795.00
INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge, InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
VALUES (2, 1200.00, 280.00, 800.00, 540.00, 55.00, 1795.00, 'Paid');

-- Appt 3 | Patient 3 | no insurance
-- Med: 21*5 = 105 | Lab: 350
-- GST: 105*0.05 + 350*0.12 = 5.25+42.00 = 47.25
-- Final: 800+105+350+47.25 = 1302.25
INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge, InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
VALUES (3, 800.00, 105.00, 350.00, 0.00, 47.25, 1302.25, 'Unpaid');

-- Appt 5 | Patient 5 | no insurance
-- Med: 15*5 = 75 | Lab: 350
-- GST: 75*0.05 + 350*0.12 = 3.75+42.00 = 45.75
-- Final: 700+75+350+45.75 = 1170.75
INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge, InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
VALUES (5, 700.00, 75.00, 350.00, 0.00, 45.75, 1170.75, 'Paid');

-- Appt 6 | Patient 1 | 40% insurance
-- Med: 20*10 = 200 | Lab: 0
-- Discount: 200*0.40 = 80
-- GST: (200-80)*0.05 = 6.00
-- Final: 1200+120+0+6 = 1326.00
INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge, InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
VALUES (6, 1200.00, 200.00, 0.00, 80.00, 6.00, 1326.00, 'Unpaid');

-- Appt 7 | Patient 2 | 50% insurance
-- Med: 60*20 = 1200 | Lab: 600
-- Discount: (1200+600)*0.50 = 900
-- GST: (1200-600)*0.05 + (600-300)*0.12 = 30.00+36.00 = 66.00
-- Final: 1500+600+300+66 = 2466.00
INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge, InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
VALUES (7, 1500.00, 1200.00, 600.00, 900.00, 66.00, 2466.00, 'Paid');

-- Appt 9 | Patient 4 | 30% insurance
-- Med: 180*12 = 2160 | Lab: 150
-- Discount: (2160+150)*0.30 = 693
-- GST: (2160-648)*0.05 + (150-45)*0.12 = 75.60+12.60 = 88.20
-- Final: 800+1512+105+88.20 = 2505.20
INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge, InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
VALUES (9, 800.00, 2160.00, 150.00, 693.00, 88.20, 2505.20, 'Unpaid');

-- Appt 10 | Patient 5 | no insurance
-- Med: 0 | Lab: 350
-- GST: 350*0.12 = 42.00
-- Final: 1400+0+350+42 = 1792.00
INSERT INTO Billing (AppointmentID, ConsultationCharge, MedicineCharge, LabCharge, InsuranceDiscount, TotalGST, FinalAmount, PaymentStatus)
VALUES (10, 1400.00, 0.00, 350.00, 0.00, 42.00, 1792.00, 'Unpaid');
GO
