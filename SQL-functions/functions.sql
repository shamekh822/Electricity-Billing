-- Name: Shamekh Ali
-- Roll No: 25100131
-- Section: 2

-- The file contains the template for the functions to be implemented in the assignment. DO NOT MODIFY THE FUNCTION SIGNATURES. Only need to add your implementation within the function bodies.

----------------------------------------------------------
-- 2.1.1 Function to compute billing days
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_PeakAmount (
    p_ConnectionID  IN VARCHAR2,
    p_BillingMonth  IN NUMBER,
    p_BillingYear   IN NUMBER,
    p_BillIssueDate IN DATE
) RETURN NUMBER

IS
-- varaible declarations
    v_MinUnits NUMBER;
    v_Rate NUMBER;
    v_MinAmount NUMBER;
    v_BillingDays NUMBER;
    v_PeakUnitsImported NUMBER;
    v_AHPC NUMBER;
    v_AdditionalUnitsPeakImport NUMBER;
    v_PeakAmount NUMBER;


BEGIN
-- main processing logic

-- calculating the no. of days in the billing period based on the conection ID, month, and yaer
v_BillingDays := fun_compute_BillingDays(p_ConnectionID, p_BillingMonth, p_BillingYear);

-- calculating the no. of days in the billing period based on the connection ID, month, and year
v_PeakUnitsImported := fun_compute_ImportPeakUnits(p_ConnectionID, p_BillingMonth, p_BillingYear);

-- calculating the avg. hourly peak consumption (AHPC) by dividing peak units by billing days and scaling to 24 hours
-- what this does is that this gives us the typical energy usage per hour during paek times for the customer
v_AHPC := (v_PeakUnitsImported / v_BillingDays) * 24;

-- using the select statement to look up the tariff details based on the customer’s connection type, biling data range and customer’s avg. hourly peak consumption (AHPC).

SELECT MinUnit, RatePerUnit, MinAmount
    INTO v_MinUnits, v_Rate, v_MinAmount
    FROM Tariff
    WHERE ConnectionTypeCode = (SELECT ConnectionTypeCode
                                FROM Connections
                                WHERE ConnectionID = p_ConnectionID)
      AND p_BillIssueDate BETWEEN StartDate AND EndDate
      AND TariffType = 1
      AND v_AHPC BETWEEN ThresholdLow_perHour AND ThresholdHigh_perHour;


-- calculating aditional units by subtracting the min units from the total peak units imported. (Formula 9 from the handout)
-- this determines if the customer used more than the min required unitsd and if so, then by how much 
v_AdditionalUnitsPeakImport := v_PeakUnitsImported - (v_MinUnits * v_BillingDays )/30;

-- calculating the peak amount to bill the customer for additional unitsd above the minimum at the rate per unit and add a portion of the min amount based on billing days
v_PeakAmount := (v_AdditionalUnitsPeakImport * v_Rate) + (v_MinAmount * v_BillingDays )/30;

-- rounfing to 2dp
RETURN ROUND(v_PeakAmount, 2);

EXCEPTION
-- exception handling
    WHEN NO_DATA_FOUND THEN
        RETURN -1; 
    WHEN OTHERS THEN
        RETURN -1;


END fun_compute_PeakAmount;


----------------------------------------------------------
-- 2.1.2 Function to compute Import_PeakUnits
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_ImportPeakUnits (
    p_ConnectionID IN VARCHAR2,
    p_BillingMonth IN NUMBER,
    p_BillingYear  IN NUMBER
) RETURN NUMBER

IS
-- varaible declarations
    v_Curr_ImportPeakReadings NUMBER;
    v_Prev_ImportPeakReadings NUMBER;
    v_PeakUnitsImported NUMBER:=0;

BEGIN
-- main processing logic

-- finding the max import peak reading for the current billing month
    SELECT MAX(Import_PeakReading)
    INTO v_Curr_ImportPeakReadings
    FROM MeterReadings
    WHERE ConnectionID = p_ConnectionID
      AND EXTRACT(MONTH FROM TStamp) = p_BillingMonth -- check if the timestamp month matches the billing montj
      AND EXTRACT(YEAR FROM TStamp) = p_BillingYear; -- vheck if the timestamp year matches the billing year

-- findign the max import peak reading for the previous month
    SELECT MAX(Import_PeakReading)
        INTO v_Prev_ImportPeakReadings
        FROM MeterReadings
        WHERE ConnectionID = p_ConnectionID
        AND EXTRACT(MONTH FROM TStamp) =                       -- checkign if the previous month is dec of the last year or simply the prior month
            CASE WHEN p_BillingMonth = 1 THEN 12 ELSE p_BillingMonth - 1 END  -- if billing month is January, set to dec, otherwise use previous month. 
        AND EXTRACT(YEAR FROM TStamp) =  -- adjust the year accordinlgy
            CASE WHEN p_BillingMonth = 1 THEN p_BillingYear - 1 ELSE p_BillingYear END;


-- calculating the peak units imported by subtracting previous month's reading from the current month's reading which gives the actual number of units imported in the current billing period
     IF v_Curr_ImportPeakReadings IS NOT NULL AND v_Prev_ImportPeakReadings IS NOT NULL THEN
        v_PeakUnitsImported := v_Curr_ImportPeakReadings - v_Prev_ImportPeakReadings;
    ELSE
        DBMS_OUTPUT.PUT_LINE('Missing readings for this or previous month');
        RETURN -1;
    END IF;

    RETURN v_PeakUnitsImported;

        

EXCEPTION
-- exception handling
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('No meter reading found');
        RETURN -1;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Unexpected Error');
        RETURN -1;


END fun_compute_ImportPeakUnits;

----------------------------------------------------------
-- 2.1.3 Function to compute Import_OffPeakUnits
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_ImportOffPeakUnits (
    p_ConnectionID IN VARCHAR2,
    p_BillingMonth IN NUMBER,
    p_BillingYear  IN NUMBER
) RETURN NUMBER

IS
-- varaible declarations
    v_Curr_ImportOffPeakReadings NUMBER;
    v_Prev_ImportOffPeakReadings NUMBER;
    v_OffPeakUnitsImported NUMBER := 0;

BEGIN
-- main processing logic

    SELECT MAX(Import_OffPeakReading)
    INTO v_Curr_ImportOffPeakReadings
    FROM MeterReadings
    WHERE ConnectionID = p_ConnectionID
      AND EXTRACT(MONTH FROM TStamp) = p_BillingMonth
      AND EXTRACT(YEAR FROM TStamp) = p_BillingYear;

    SELECT MAX(Import_OffPeakReading)
    INTO v_Prev_ImportOffPeakReadings
    FROM MeterReadings
    WHERE ConnectionID = p_ConnectionID
      AND EXTRACT(MONTH FROM TStamp) = 
          CASE WHEN p_BillingMonth = 1 THEN 12 ELSE p_BillingMonth - 1 END
      AND EXTRACT(YEAR FROM TStamp) = 
          CASE WHEN p_BillingMonth = 1 THEN p_BillingYear - 1 ELSE p_BillingYear END;

    IF v_Curr_ImportOffPeakReadings IS NOT NULL AND v_Prev_ImportOffPeakReadings IS NOT NULL THEN
        v_OffPeakUnitsImported := v_Curr_ImportOffPeakReadings - v_Prev_ImportOffPeakReadings;
    ELSE
        RETURN -1;
    END IF;

    RETURN v_OffPeakUnitsImported;

EXCEPTION
-- exception handling
    WHEN OTHERS THEN
        RETURN -1;
END fun_compute_ImportOffPeakUnits;



----------------------------------------------------------
-- 2.1.4 Function to compute Export_OffPeakUnits
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_ExportOffPeakUnits (
    p_ConnectionID IN VARCHAR2,
    p_BillingMonth IN NUMBER,
    p_BillingYear IN NUMBER
) RETURN NUMBER

IS
-- varaible declarations
    v_Curr_ExportOffPeakReadings NUMBER;
    v_Prev_ExportOffPeakReadings NUMBER;
    v_OffPeakUnitsExported NUMBER := 0;

BEGIN
-- main processing logic
    SELECT MAX(Export_OffPeakReading)
    INTO v_Curr_ExportOffPeakReadings
    FROM MeterReadings
    WHERE ConnectionID = p_ConnectionID
      AND EXTRACT(MONTH FROM TStamp) = p_BillingMonth
      AND EXTRACT(YEAR FROM TStamp) = p_BillingYear;

    SELECT MAX(Export_OffPeakReading)
    INTO v_Prev_ExportOffPeakReadings
    FROM MeterReadings
    WHERE ConnectionID = p_ConnectionID
      AND EXTRACT(MONTH FROM TStamp) = 
          CASE WHEN p_BillingMonth = 1 THEN 12 ELSE p_BillingMonth - 1 END
      AND EXTRACT(YEAR FROM TStamp) = 
          CASE WHEN p_BillingMonth = 1 THEN p_BillingYear - 1 ELSE p_BillingYear END;

    IF v_Curr_ExportOffPeakReadings IS NOT NULL AND v_Prev_ExportOffPeakReadings IS NOT NULL THEN
        v_OffPeakUnitsExported := v_Curr_ExportOffPeakReadings - v_Prev_ExportOffPeakReadings;
    ELSE
        RETURN -1;
    END IF;

    RETURN v_OffPeakUnitsExported;

EXCEPTION
-- exception handling

    WHEN OTHERS THEN
        RETURN -1;
END fun_compute_ExportOffPeakUnits;

----------------------------------------------------------
-- 2.2.1 Function to compute PeakAmount
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_PeakAmount (
    p_ConnectionID  IN VARCHAR2,
    p_BillingMonth  IN NUMBER,
    p_BillingYear   IN NUMBER,
    p_BillIssueDate IN DATE
) RETURN NUMBER

IS
-- varaible declarations
    v_MinUnits NUMBER;
    v_Rate NUMBER;
    v_MinAmount NUMBER;
    v_BillingDays NUMBER;
    v_PeakUnitsImported NUMBER;
    v_AHPC NUMBER;
    v_AdditionalUnitsPeakImport NUMBER;
    v_PeakAmount NUMBER;


BEGIN
-- main processing logic

    v_BillingDays := fun_compute_BillingDays(p_ConnectionID, p_BillingMonth, p_BillingYear);
    v_PeakUnitsImported := fun_compute_ImportPeakUnits(p_ConnectionID, p_BillingMonth, p_BillingYear);
    v_AHPC := (v_PeakUnitsImported / v_BillingDays) * 24;

    SELECT MinUnit, RatePerUnit, MinAmount
    INTO v_MinUnits, v_Rate, v_MinAmount
    FROM Tariff
    WHERE ConnectionTypeCode = (SELECT ConnectionTypeCode
                                FROM Connections
                                WHERE ConnectionID = p_ConnectionID)
      AND p_BillIssueDate BETWEEN StartDate AND EndDate
      AND TariffType = 1
      AND v_AHPC BETWEEN ThresholdLow_perHour AND ThresholdHigh_perHour;

    v_AdditionalUnitsPeakImport := v_PeakUnitsImported - (v_MinUnits * v_BillingDays )/30;
    v_PeakAmount := (v_AdditionalUnitsPeakImport * v_Rate) + (v_MinAmount * v_BillingDays )/30;
    RETURN ROUND(v_PeakAmount, 2);

EXCEPTION
-- exception handling
    WHEN NO_DATA_FOUND THEN
        RETURN -1; 
    WHEN OTHERS THEN
        RETURN -1;


END fun_compute_PeakAmount;

/

----------------------------------------------------------
-- 2.2.2 Function to compute OffPeakAmount
----------------------------------------------------------

CREATE OR REPLACE FUNCTION fun_compute_OffPeakAmount (
    p_ConnectionID IN VARCHAR2,
    p_BillingMonth IN NUMBER,
    p_BillingYear IN NUMBER,
    p_BillIssueDate IN DATE
)
RETURN NUMBER
IS
-- varaible declarations
    v_BillingPeriodDays NUMBER;
    v_ImportedOffPeakUnits NUMBER;
    v_ExportedOffPeakUnits NUMBER;
    v_AdditionalImportedUnitsOffPeak NUMBER;
    v_AdditionalExportedUnitsOffPeak NUMBER;
    v_ImportTariffUnits NUMBER;
    v_ExportTariffUnits NUMBER;
    v_ImportRatePerUnit NUMBER;
    v_ExportRatePerUnit NUMBER;
    v_ImportMinimumCharge NUMBER;
    v_ExportMinimumCharge NUMBER;
    v_TotalImportOffPeakCharge NUMBER;
    v_TotalExportOffPeakCredit NUMBER;
    v_NetOffPeakCharge NUMBER;

BEGIN
-- main processing logic

    v_BillingPeriodDays := fun_compute_BillingDays(p_ConnectionID, p_BillingMonth, p_BillingYear);
    v_ImportedOffPeakUnits := fun_compute_ImportOffPeakUnits(p_ConnectionID, p_BillingMonth, p_BillingYear);
    v_ExportedOffPeakUnits := fun_compute_ExportOffPeakUnits(p_ConnectionID, p_BillingMonth, p_BillingYear);
    
    SELECT MinUnit, RatePerUnit, MinAmount
    INTO v_ImportTariffUnits, v_ImportRatePerUnit, v_ImportMinimumCharge
    FROM Tariff
    WHERE TariffType = 2 
      AND StartDate <= p_BillIssueDate
      AND EndDate >= p_BillIssueDate
      AND ConnectionTypeCode = (SELECT ConnectionTypeCode FROM Connections WHERE ConnectionID = p_ConnectionID)
      AND ((v_ImportedOffPeakUnits / (v_BillingPeriodDays * 24)) BETWEEN ThresholdLow_perHour AND ThresholdHigh_perHour)
      AND ROWNUM = 1;

    SELECT MinUnit, RatePerUnit, MinAmount
    INTO v_ExportTariffUnits, v_ExportRatePerUnit, v_ExportMinimumCharge
    FROM Tariff
    WHERE TariffType = 2 
      AND StartDate <= p_BillIssueDate
      AND EndDate >= p_BillIssueDate
      AND ConnectionTypeCode = (SELECT ConnectionTypeCode FROM Connections WHERE ConnectionID = p_ConnectionID)
      AND ((v_ExportedOffPeakUnits / (v_BillingPeriodDays * 24)) BETWEEN ThresholdLow_perHour AND ThresholdHigh_perHour)
      AND ROWNUM = 1;

    v_AdditionalImportedUnitsOffPeak := v_ImportedOffPeakUnits - (v_ImportTariffUnits * v_BillingPeriodDays / 30);
    v_AdditionalExportedUnitsOffPeak := v_ExportedOffPeakUnits - (v_ExportTariffUnits * v_BillingPeriodDays / 30);

    v_TotalImportOffPeakCharge := (v_AdditionalImportedUnitsOffPeak * v_ImportRatePerUnit) + (v_ImportMinimumCharge * v_BillingPeriodDays / 30);
    v_TotalExportOffPeakCredit := (v_AdditionalExportedUnitsOffPeak * v_ExportRatePerUnit) + (v_ExportMinimumCharge * v_BillingPeriodDays / 30);

    v_NetOffPeakCharge := v_TotalImportOffPeakCharge - v_TotalExportOffPeakCredit;

    RETURN ROUND(v_NetOffPeakCharge, 2);

EXCEPTION
-- exception handling

    WHEN NO_DATA_FOUND THEN
        RETURN -1;
    WHEN OTHERS THEN
        RETURN -1;
END fun_compute_OffPeakAmount;


----------------------------------------------------------
-- 2.3.1 Function to compute TaxAmount
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_TaxAmount (
    p_ConnectionID  IN VARCHAR2,
    p_BillingMonth  IN NUMBER,
    p_BillingYear   IN NUMBER,
    p_BillIssueDate IN DATE,
    p_PeakAmount    IN NUMBER,
    p_OffPeakAmount IN NUMBER
) RETURN NUMBER

IS
-- varaible declarations
    v_TotalBillAmount  NUMBER;        
    v_TaxAmount        NUMBER := 0;  
    v_RatePerUnit      NUMBER;        
    CURSOR cur_TaxRates IS
        SELECT Rate
        FROM TaxRates
        WHERE ConnectionTypeCode = (SELECT ConnectionTypeCode 
                                     FROM Connections
                                     WHERE ConnectionID = p_ConnectionID)
          AND p_BillIssueDate BETWEEN StartDate AND EndDate;
BEGIN
-- main processing logic

    v_TotalBillAmount := p_PeakAmount + p_OffPeakAmount; 
    FOR rec_TaxRate IN cur_TaxRates LOOP             
        v_TaxAmount := v_TaxAmount + (v_TotalBillAmount * rec_TaxRate.Rate); 
    END LOOP;

    RETURN ROUND(v_TaxAmount, 2);

EXCEPTION
-- exception handling
    WHEN NO_DATA_FOUND THEN
        RETURN -1; 
    WHEN OTHERS THEN
        RETURN -1;

END fun_compute_TaxAmount;

/


----------------------------------------------------------
-- 2.3.2 Function to compute FixedFee Amount
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_FixedFee (
    p_ConnectionID  IN VARCHAR2,
    p_BillingMonth  IN NUMBER,
    p_BillingYear   IN NUMBER,
    p_BillIssueDate IN DATE
) RETURN NUMBER

IS
-- varaible declarations
    v_TotalFixedCharges NUMBER := 0; 

    CURSOR cur_FixedChargeRates IS
        SELECT FixedFee
        FROM FixedCharges
        WHERE ConnectionTypeCode = (
            SELECT ConnectionTypeCode
            FROM Connections
            WHERE ConnectionID = p_ConnectionID
        )
        AND p_BillIssueDate BETWEEN StartDate AND EndDate;

BEGIN
-- main processing logic
    FOR rec_FixedCharge IN cur_FixedChargeRates LOOP
        v_TotalFixedCharges := v_TotalFixedCharges + rec_FixedCharge.FixedFee;  
    END LOOP;

    RETURN ROUND(v_TotalFixedCharges, 2);


EXCEPTION
-- exception handling
    WHEN NO_DATA_FOUND THEN
        RETURN -1; 
    WHEN OTHERS THEN
        RETURN -1;

END fun_compute_FixedFee;

----------------------------------------------------------
-- 2.3.3 Function to compute Arrears
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_Arrears (
    p_ConnectionID  IN VARCHAR2,
    p_BillingMonth  IN NUMBER,
    p_BillingYear   IN NUMBER,
    p_BillIssueDate IN DATE
) RETURN NUMBER
IS
-- varaible declarations
    v_OutstandingArrears NUMBER := 0;
    v_PrevBillID NUMBER;
    v_BeforeDueAmount NUMBER := 0;
    v_AfterDueAmount NUMBER := 0;
    v_PaidAmount NUMBER := 0;
    v_PrevMonth NUMBER;
    v_PrevYear NUMBER;
    v_PaymentRecords NUMBER := 0;
    v_BalanceDue NUMBER := 0;
    v_BillDueDate DATE;
    v_FirstPaymentDate DATE;

BEGIN
-- main processing logic

    v_PrevMonth := CASE WHEN p_BillingMonth = 1 THEN 12 ELSE p_BillingMonth - 1 END;
    v_PrevYear := CASE WHEN p_BillingMonth = 1 THEN p_BillingYear - 1 ELSE p_BillingYear END;

    SELECT MAX(BillID)
    INTO v_PrevBillID
    FROM Bill
    WHERE ConnectionID = p_ConnectionID
      AND BillingMonth = v_PrevMonth
      AND BillingYear = v_PrevYear;

    IF v_PrevBillID IS NULL THEN
        RETURN -1;
    END IF;

    SELECT TotalAmount_BeforeDueDate, TotalAmount_AfterDueDate, DueDate
    INTO v_BeforeDueAmount, v_AfterDueAmount, v_BillDueDate
    FROM Bill
    WHERE BillID = v_PrevBillID;

    SELECT COUNT(*), COALESCE(SUM(AmountPaid), 0), MIN(PaymentDate)
    INTO v_PaymentRecords, v_PaidAmount, v_FirstPaymentDate
    FROM PaymentDetails
    WHERE BillID = v_PrevBillID;

    IF v_PaymentRecords > 0 THEN
        IF v_FirstPaymentDate <= v_BillDueDate THEN
            v_BalanceDue := v_BeforeDueAmount - v_PaidAmount;
        ELSE
            v_BalanceDue := v_AfterDueAmount - v_PaidAmount;
        END IF;

        IF v_BalanceDue > 0 THEN
            v_OutstandingArrears := v_BalanceDue;
        ELSE
            v_OutstandingArrears := 0;
        END IF;
    ELSE
        v_OutstandingArrears := v_AfterDueAmount;
    END IF;

    RETURN ROUND(v_OutstandingArrears, 2);

EXCEPTION
-- exception handling

    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('No data found for ConnectionID: ' || p_ConnectionID);
        RETURN -1; 
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('An unexpected error occurred.');
        RETURN -1;
END fun_compute_Arrears;
/
----------------------------------------------------------
-- 2.3.4 Function to compute SubsidyAmount
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_compute_SubsidyAmount (
    p_ConnectionID       IN VARCHAR2,
    p_BillingMonth       IN NUMBER,
    p_BillingYear        IN NUMBER,
    p_BillIssueDate      IN DATE,
    p_ImportPeakUnits    IN NUMBER,
    p_ImportOffPeakUnits IN NUMBER
) RETURN NUMBER

IS
-- varaible declarations
    v_TotalSubsidy       NUMBER := 0;       
    v_TotalUnits         NUMBER;           
    v_NumBillingDays     NUMBER;           
    v_SubsidyRate        NUMBER;       
    CURSOR c_SubsidyRates IS
        SELECT RatePerUnit
        FROM Subsidy
        WHERE ConnectionTypeCode = (
            SELECT ConnectionTypeCode
            FROM Connections
            WHERE ConnectionID = p_ConnectionID
        )
        AND StartDate <= p_BillIssueDate 
        AND EndDate >= p_BillIssueDate;

BEGIN
-- main processing logic
    v_NumBillingDays := fun_compute_BillingDays(p_ConnectionID, p_BillingMonth, p_BillingYear);
    v_TotalUnits := p_ImportPeakUnits + p_ImportOffPeakUnits;
    FOR record IN c_SubsidyRates LOOP
        v_TotalSubsidy := v_TotalSubsidy + (v_TotalUnits * record.RatePerUnit);
    END LOOP;

    RETURN ROUND(v_TotalSubsidy, 2);

EXCEPTION
-- exception handling

    WHEN NO_DATA_FOUND THEN
        RETURN -1;
    WHEN OTHERS THEN
        RETURN -1;

END fun_compute_SubsidyAmount;

/

----------------------------------------------------------
-- 2.4.1 Function to generate Bill by inserting records in the Bill Table
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_Generate_Bill (
    p_BillID        IN NUMBER,
    p_ConnectionID  IN VARCHAR2,
    p_BillingMonth  IN NUMBER,
    p_BillingYear   IN NUMBER,
    p_BillIssueDate IN DATE
) RETURN NUMBER
IS
-- varaible declarations

    v_BillingPeriodDays NUMBER;
    v_PeakUsageAmount NUMBER;
    v_OffPeakUsageAmount NUMBER;
    v_TotalTaxAmount NUMBER;
    v_ConnectionFixedFee NUMBER;
    v_SubsidyDiscountAmount NUMBER;
    v_PreviousArrearsAmount NUMBER;
    v_AdjustmentAmount NUMBER := 0;
    v_AmountBeforeDueDate NUMBER;
    v_AmountAfterDueDate NUMBER;
    v_BillDueDate DATE;
    v_ImportedPeakUnits NUMBER;
    v_ImportedOffPeakUnits NUMBER;
    v_ExportedOffPeakUnits NUMBER;

BEGIN
-- main processing logic

    v_BillDueDate := p_BillIssueDate + 10;
    v_ImportedPeakUnits := fun_compute_ImportPeakUnits(p_ConnectionID, p_BillingMonth, p_BillingYear);
    v_ImportedOffPeakUnits := fun_compute_ImportOffPeakUnits(p_ConnectionID, p_BillingMonth, p_BillingYear);
    v_ExportedOffPeakUnits := fun_compute_ExportOffPeakUnits(p_ConnectionID, p_BillingMonth, p_BillingYear);
   
    IF v_ImportedPeakUnits < 0 OR v_ImportedOffPeakUnits < 0 OR v_ExportedOffPeakUnits < 0 THEN
        RETURN -1;
    END IF;

    v_BillingPeriodDays := fun_compute_BillingDays(p_ConnectionID, p_BillingMonth, p_BillingYear);
    IF v_BillingPeriodDays <= 0 THEN
        RETURN -1;
    END IF;

    v_OffPeakUsageAmount := fun_compute_OffPeakAmount(p_ConnectionID, p_BillingMonth, p_BillingYear, p_BillIssueDate);
    v_PeakUsageAmount := fun_compute_PeakAmount(p_ConnectionID, p_BillingMonth, p_BillingYear, p_BillIssueDate);
    
    IF v_PeakUsageAmount < 0 OR v_OffPeakUsageAmount < 0 THEN
        RETURN -1;
    END IF;

    v_TotalTaxAmount := fun_compute_TaxAmount(p_ConnectionID, p_BillingMonth, p_BillingYear, p_BillIssueDate, v_PeakUsageAmount, v_OffPeakUsageAmount);

    IF v_TotalTaxAmount < 0 THEN
        RETURN -1;
    END IF;
    
    v_SubsidyDiscountAmount := fun_compute_SubsidyAmount(p_ConnectionID, p_BillingMonth, p_BillingYear, p_BillIssueDate, v_ImportedPeakUnits, v_ImportedOffPeakUnits);
    IF v_SubsidyDiscountAmount < 0 THEN
        RETURN -1;
    END IF;

    v_ConnectionFixedFee := fun_compute_FixedFee(p_ConnectionID, p_BillingMonth, p_BillingYear, p_BillIssueDate);
    IF v_ConnectionFixedFee < 0 THEN
        RETURN -1;
    END IF;

    v_PreviousArrearsAmount := fun_compute_Arrears(p_ConnectionID, p_BillingMonth, p_BillingYear, p_BillIssueDate);
    IF v_PreviousArrearsAmount < 0 THEN
        RETURN -1;
    END IF;

    v_AmountBeforeDueDate := (v_PeakUsageAmount + v_OffPeakUsageAmount + v_TotalTaxAmount + v_ConnectionFixedFee) 
                             - (v_SubsidyDiscountAmount + v_AdjustmentAmount) 
                             + v_PreviousArrearsAmount;

    v_AmountAfterDueDate := v_AmountBeforeDueDate * 1.10;

    INSERT INTO Bill (
        BillID, ConnectionID,
        BillingMonth, BillingYear, BillIssueDate,
        Import_PeakUnits, Import_OffPeakUnits, Export_OffPeakUnits,
        PeakAmount, OffPeakAmount, 
        FixedFee, TaxAmount, Arrears,
        SubsidyAmount, AdjustmentAmount, DueDate, 
        TotalAmount_BeforeDueDate, TotalAmount_AfterDueDate
    ) VALUES (
        p_BillID, p_ConnectionID, p_BillingMonth, 
        p_BillingYear, p_BillIssueDate,
        v_ImportedPeakUnits, v_ImportedOffPeakUnits, 
        v_ExportedOffPeakUnits,
        v_PeakUsageAmount, v_OffPeakUsageAmount, 
        v_ConnectionFixedFee, v_TotalTaxAmount, v_PreviousArrearsAmount,
        v_SubsidyDiscountAmount, v_AdjustmentAmount, 
        v_BillDueDate, v_AmountBeforeDueDate, v_AmountAfterDueDate
    );
    RETURN 1;

EXCEPTION
-- exception handling
    WHEN OTHERS THEN
        RETURN -1;
END fun_Generate_Bill;

/

----------------------------------------------------------
-- 2.4.2 Function for generating monthly bills of all consumers
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_batch_Billing (
    p_BillingMonth  IN NUMBER,
    p_BillingYear   IN NUMBER,
    p_BillIssueDate IN DATE
) RETURN NUMBER

IS
-- varaible declarations
    v_CurrentBillID        NUMBER := 0;     
    v_CurrentConnectionID   VARCHAR2(50); 
    v_FunctionResult        NUMBER;     
    v_TotalBillsGenerated   NUMBER := 0;

    CURSOR active_connections IS
        SELECT BillID, ConnectionID
        FROM Bill
        WHERE BillingMonth = p_BillingMonth
        AND   BillingYear = p_BillingYear
        AND   ConnectionID IN (
            SELECT ConnectionID
            FROM Connections
            WHERE status = 'Active'
        );

BEGIN
-- main processing logic
    FOR record IN active_connections LOOP
        v_FunctionResult := fun_Generate_Bill(record.BillID, record.ConnectionID, p_BillingMonth, p_BillingYear, p_BillIssueDate);
        v_TotalBillsGenerated := v_TotalBillsGenerated + 1;
    END LOOP;

    RETURN v_TotalBillsGenerated;

EXCEPTION
-- exception handling
    WHEN NO_DATA_FOUND THEN
        RETURN -1;
    WHEN OTHERS THEN
        RETURN -1;

END fun_batch_Billing;

/

----------------------------------------------------------
-- 3.1.1 Function to process and record Payment
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_process_Payment (
    p_BillID          IN NUMBER,
    p_PaymentDate     IN DATE,
    p_PaymentMethodID IN NUMBER,
    p_AmountPaid      IN NUMBER
) RETURN NUMBER
IS
-- varaible declarations

    v_BillTotalAmountBeforeDueDate NUMBER := 0;
    v_BillTotalAmountAfterDueDate NUMBER := 0;
    v_TotalPaymentAmount NUMBER := 0;
    v_BillDueDate DATE;
    v_OutstandingBalance NUMBER := 0;
    v_CurrentPaymentStatus VARCHAR2(50);
    v_ArrearsAmount NUMBER := 0;

BEGIN
-- main processing logic

    SELECT TotalAmount_BeforeDueDate, TotalAmount_AfterDueDate, DueDate
    INTO v_BillTotalAmountBeforeDueDate, v_BillTotalAmountAfterDueDate, v_BillDueDate
    FROM Bill
    WHERE BillID = p_BillID;

    SELECT COALESCE(SUM(AmountPaid), 0)
    INTO v_TotalPaymentAmount
    FROM PaymentDetails
    WHERE BillID = p_BillID;

    v_TotalPaymentAmount := v_TotalPaymentAmount + p_AmountPaid;

    IF p_PaymentDate <= v_BillDueDate THEN
        v_OutstandingBalance := v_BillTotalAmountBeforeDueDate - v_TotalPaymentAmount;
    ELSE
        v_OutstandingBalance := v_BillTotalAmountAfterDueDate - v_TotalPaymentAmount;
    END IF;

    IF v_OutstandingBalance <= 0 THEN
        v_CurrentPaymentStatus := 'Fully Paid';
    ELSE
        v_CurrentPaymentStatus := 'Partially Paid';
        v_ArrearsAmount := v_OutstandingBalance;
    END IF;

    IF v_ArrearsAmount > 0 THEN
        UPDATE Bill
        SET Arrears = v_ArrearsAmount
        WHERE BillID = p_BillID;
    END IF;

    INSERT INTO PaymentDetails 
    (
        BillID, PaymentDate, PaymentStatus, PaymentMethodID, AmountPaid
    ) VALUES 
    (
        p_BillID, p_PaymentDate, v_CurrentPaymentStatus, p_PaymentMethodID, p_AmountPaid
    );

    RETURN 1;

EXCEPTION
-- exception handling

    WHEN NO_DATA_FOUND THEN
        RETURN -1;
    WHEN OTHERS THEN
        RETURN -1;
END fun_process_Payment;

----------------------------------------------------------
-- 4.1.1 Function to make Bill adjustment
----------------------------------------------------------
CREATE OR REPLACE FUNCTION fun_adjust_Bill (
    p_AdjustmentID       IN NUMBER,
    p_BillID             IN NUMBER,
    p_AdjustmentDate     IN DATE,
    p_OfficerName        IN VARCHAR2,
    p_OfficerDesignation IN VARCHAR2,
    p_OriginalBillAmount IN NUMBER,
    p_AdjustmentAmount   IN NUMBER,
    p_AdjustmentReason   IN VARCHAR2
) RETURN NUMBER

IS
-- varaible declarations
    v_TotalAmountBeforeDue NUMBER;      
    v_TotalAmountAfterDue  NUMBER;  

BEGIN
-- main processing logic

    v_TotalAmountBeforeDue := p_OriginalBillAmount - p_AdjustmentAmount;
    v_TotalAmountAfterDue := v_TotalAmountBeforeDue * 1.10;

    UPDATE Bill
    SET TotalAmount_BeforeDueDate = v_TotalAmountBeforeDue,
        TotalAmount_AfterDueDate = v_TotalAmountAfterDue,
        AdjustmentAmount = p_AdjustmentAmount
    WHERE BillID = p_BillID;

    INSERT INTO BillAdjustments (
        AdjustmentID,
        BillID,
        AdjustmentDate,
        OfficerName,
        OfficerDesignation,
        OriginalBillAmount,
        AdjustmentAmount,
        AdjustmentReason
    )
    VALUES (
        p_AdjustmentID,
        p_BillID,
        p_AdjustmentDate,
        p_OfficerName,
        p_OfficerDesignation,
        p_OriginalBillAmount,
        p_AdjustmentAmount,
        p_AdjustmentReason
    );

    RETURN 1;

EXCEPTION
-- exception handling

    WHEN NO_DATA_FOUND THEN
        RETURN -1;  

    WHEN OTHERS THEN
        RETURN -1;

END fun_adjust_Bill;