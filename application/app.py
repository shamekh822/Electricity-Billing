from fastapi import FastAPI, Request, Form
from fastapi.middleware.cors import CORSMiddleware 
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles

import datetime
import os
import logging
import oracledb
import uvicorn


import uuid 

d = os.environ.get("ORACLE_HOME")               # Defined by the file `oic_setup.sh`
oracledb.init_oracle_client(lib_dir=d)          # Thick mode

# These environment variables come from `env.sh` file.
user_name = os.environ.get("DB_USERNAME")
user_pswd = os.environ.get("DB_PASSWORD")
db_alias  = os.environ.get("DB_ALIAS")

# make sure to setup connection with the DATABASE SERVER FIRST. refer to python-oracledb documentation for more details on how to connect, and run sql queries and PL/SQL procedures.
connection = oracledb.connect(
    user=user_name,
    password=user_pswd,
    dsn=db_alias,
)

app = FastAPI()

logger = logging.getLogger('uvicorn.error')
logger.setLevel(logging.DEBUG)

origins = ['*']

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
) 
app.mount("/static", StaticFiles(directory="static"), name="static")

templates = Jinja2Templates(directory="templates")


# -----------------------------
# API Endpoints
# -----------------------------

# ---------- GET methods for the pages ----------
@app.get("/", response_class=HTMLResponse)
async def get_index(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})

# Bill payment page
@app.get("/bill-payment", response_class=HTMLResponse)
async def get_bill_payment(request: Request):
    return templates.TemplateResponse("bill_payment.html", {"request": request})

# Bill generation page
@app.get("/bill-retrieval", response_class=HTMLResponse)
async def get_bill_retrieval(request: Request):
    return templates.TemplateResponse("bill_retrieval.html", {"request": request})

# Adjustments page
@app.get("/bill-adjustments", response_class=HTMLResponse)
async def get_bill_adjustment(request: Request):
    return templates.TemplateResponse("adjust_bill.html", {"request": request})


# ---------- POST methods for the pages ----------
@app.post("/bill-payment", response_class=HTMLResponse)
async def post_bill_payment(
    request: Request,
    bill_id: int = Form(...),
    amount: float = Form(...),
    payment_method_id: int = Form(...),
):
    try:

        cursor = connection.cursor()

        bill_query = """
            SELECT 
                TotalAmount_BeforeDueDate, TotalAmount_AfterDueDate, DueDate
            FROM 
                Bill
            WHERE 
                BillID = :bill_id
        """
        cursor.execute(bill_query, [bill_id])
        bill_result = cursor.fetchone()

        if not bill_result:
            return templates.TemplateResponse(
                "bill_payment.html",
                {
                    "request": request,
                    "message": f"Error: No bill found with Bill ID {bill_id}.",
                    "alert_type": "error",
                },
            )


        total_before_due_date, total_after_due_date, due_date = bill_result

        method_query = """
            SELECT 
                PaymentMethodDescription
            FROM 
                PaymentMethods
            WHERE 
                PaymentMethodID = :payment_method_id
        """

        cursor.execute(method_query, [payment_method_id])
        payment_method_description = cursor.fetchone()

        if payment_method_description is None:
           
            return templates.TemplateResponse(
                "bill_payment.html",
                {
                    "request": request,
                    "message": f"Error: Payment method with ID {payment_method_id} not found.",
                    "alert_type": "error",
                },
            )

     
        payment_method_description = payment_method_description[0]


  
        payment_query = """
            SELECT 
                COALESCE(SUM(AmountPaid), 0)
            FROM 
                PaymentDetails
            WHERE 
                BillID = :bill_id
        """
        cursor.execute(payment_query, [bill_id])
        totalAmount = cursor.fetchone()[0]

        
        totalAmount+=amount



        if datetime.datetime.now().date() <= due_date.date():
            outstanding_balance = total_before_due_date - totalAmount
        else:
            outstanding_balance = total_after_due_date - totalAmount



        if outstanding_balance<0:
            return templates.TemplateResponse(
                "bill_payment.html",
                {
                    "request": request,
                    "message": f"Error: You are paying more than the bill.",
                    "alert_type": "error",
                },
            )
        
        # This code is written because there is ambiguity about the case where a bill id is present in the paymentDetails table which means that the bill has been fully paid as all the bills in that table are already fully paid. However, I omitted this part due to the assumption that the amount written in that table might not be paid and instead, has to be paid. 

        # What this does is that it takes the last payment correspondint to the bill ID and then checks its payment status. If that status is already Fully Paid, it stores 0 in the outstanding balance as that means no money has to be paid. 

        # lastPayment_query = """
        #     SELECT 
        #         pd.PaymentDate,
        #         pd.PaymentStatus,
        #         pd.AmountPaid
        #     FROM 
        #         PaymentDetails pd
        #     WHERE 
        #         pd.BillID = :bill_id
        #     ORDER BY 
        #         pd.PaymentDate DESC
        #     FETCH FIRST 1 ROWS ONLY
        # """

        # cursor.execute(lastPayment_query, {"bill_id":bill_id})
        # finalPayment = cursor.fetchone()

        # if finalPayment and finalPayment[1] =='Fully Paid':
        #     outstanding_balance=0


        arrears=0

        if outstanding_balance <= 0:
            payment_status = "Fully Paid"
        else:
            payment_status = "Partially Paid"
            arrears=outstanding_balance

        
        if arrears > 0:
            bill_update_query = """
                UPDATE Bill
                SET Arrears = :arrears
                WHERE BillID = :bill_id
            """
            cursor.execute(bill_update_query, {"arrears": arrears, "bill_id": bill_id})



    
        payment_insert_query = """
            INSERT INTO PaymentDetails (
                BillID, PaymentDate, PaymentStatus, PaymentMethodID, AmountPaid
            ) VALUES (
                :bill_id, :payment_date, :payment_status, :payment_method_id, :amount
            )
        """
        cursor.execute(
            payment_insert_query,
            {
                "bill_id": bill_id,
                "payment_date": datetime.datetime.now(),
                "payment_status": payment_status,
                "payment_method_id": payment_method_id,
                "amount": amount,
            },
        )



        
        connection.commit()

    
        payment_details = {
            "bill_id": bill_id,
            "amount": amount,
            "payment_method_id": payment_method_id,
            "payment_method_description": payment_method_description,
            "payment_date": datetime.datetime.now(),
            "payment_status": payment_status,
            "outstanding_amount": max(0, outstanding_balance),
        }

    except oracledb.Error as e:
   
        print(f"Database error: {str(e)}")
        return templates.TemplateResponse(
            "bill_payment.html",
            {
                "request": request,
                "message": f"Database error: {str(e)}",
                "alert_type": "error",
            },
        )
   

 
    return templates.TemplateResponse("payment_receipt.html", {"request": request, "payment_details": payment_details})

@app.post("/bill-retrieval", response_class=HTMLResponse)
async def post_bill_retrieval(request: Request, customer_id: str = Form(...), connection_id: str = Form(...), month: str = Form(...), year: str = Form(...)):



    try:
     
        if not month.isdigit() or not 1 <= int(month) <= 12:
            raise ValueError("Invalid month. Please enter a value between 1 and 12.")


        cursor = connection.cursor()

        query = """
            SELECT 
                c.CustomerID, c.FirstName || ' ' || c.LastName AS CustomerName,
                c.Address AS CustomerAddress, c.PhoneNumber AS CustomerPhone,
                c.Email AS CustomerEmail, ct.Description AS ConnectionType,
                di.DivisionName, di.SubDivName, conn.InstallationDate,
                conn.MeterType, b.BillIssueDate, b.Net_PeakUnits, b.Net_OffPeakUnits,
                b.TotalAmount_BeforeDueDate, b.DueDate, b.TotalAmount_AfterDueDate,
                b.Arrears, b.FixedFee, b.TaxAmount
            FROM 
                Customers c
            JOIN 
                Connections conn ON c.CustomerID = conn.CustomerID
            JOIN 
                ConnectionTypes ct ON conn.ConnectionTypeCode = ct.ConnectionTypeCode
            JOIN 
                DivInfo di ON conn.DivisionID = di.DivisionID AND conn.SubDivID = di.SubDivID
            JOIN 
                Bill b ON conn.ConnectionID = b.ConnectionID
            WHERE 
                c.CustomerID = :customer_id
                AND conn.ConnectionID = :connection_id
                AND b.BillingMonth = :month
                AND b.BillingYear = :year
        """
        cursor.execute(query, [customer_id, connection_id, month, year])

        result = cursor.fetchone()
        if not result:
           
            return templates.TemplateResponse(
                "bill_retrieval.html",  
                {
                    "request": request,
                    "message": "Error: No bill found for the provided details.",
                    "alert_type": "error",  
                    "customer_id": customer_id, 
                    "connection_id": connection_id,
                    "month": month,
                    "year": year
                }
            )


        tariffs_query = """
            SELECT 
                t.TarrifDescription, t.MinUnit, t.RatePerUnit, t.MinAmount
            FROM 
                Tariff t
            JOIN 
                Connections co ON t.ConnectionTypeCode = co.ConnectionTypeCode
            WHERE 
                co.ConnectionID = :connection_id
                AND t.StartDate <= CURRENT_DATE
                AND t.EndDate >= CURRENT_DATE
        """
        cursor.execute(tariffs_query, [connection_id])
        tariffs = [
            {
                "name": row[0],
                "units": row[1],
                "rate": float(row[2]),
                "amount": float(row[3])
            }
            for row in cursor.fetchall()
        ]

        taxes_query = """
            SELECT 
                tr.TaxType, ta.AuthorityName, tr.Rate
            FROM 
                TaxRates tr
            JOIN 
                TaxAuthority ta ON tr.TaxAuthorityID = ta.TaxAuthorityID
            JOIN 
                Connections co ON tr.ConnectionTypeCode = co.ConnectionTypeCode
            WHERE 
                co.ConnectionID = :connection_id
                AND tr.StartDate <= CURRENT_DATE
                AND tr.EndDate >= CURRENT_DATE
        """
        cursor.execute(taxes_query, [connection_id])
        taxes = [
            {
                "name": row[0],
                "authority_name": row[1],
                "amount": float(row[2]), 
            }
            for row in cursor.fetchall()
        ]



        subsidies_query = """
            SELECT 
                s.SubsidyDescription, sp.ProviderName, s.RatePerUnit
            FROM 
                Subsidy s
            JOIN 
                SubsidyProvider sp ON s.ProviderID = sp.ProviderID
            JOIN 
                Connections co ON s.ConnectionTypeCode = co.ConnectionTypeCode
            WHERE 
                co.ConnectionID = :connection_id
                AND s.StartDate <= CURRENT_DATE
                AND s.EndDate >= CURRENT_DATE
        """
        cursor.execute(subsidies_query, [connection_id])
        subsidies = [
            {"name": row[0], "provider_name": row[1], "rate_per_unit": float(row[2])}
            for row in cursor.fetchall()
        ]
        
        fixed_charges_query = """
            SELECT 
                fc.FixedChargeType, fc.FixedFee
            FROM 
                FixedCharges fc
            JOIN 
                Connections co ON fc.ConnectionTypeCode = co.ConnectionTypeCode
            WHERE 
                co.ConnectionID = :connection_id
                AND fc.StartDate <= CURRENT_DATE
                AND fc.EndDate >= CURRENT_DATE
        """
        cursor.execute(fixed_charges_query, [connection_id])
        fixed_fee = [
            {"name": row[0], "amount": float(row[1])}
            for row in cursor.fetchall()
        ]
        
      
        previous_bills_query = """
            SELECT 
                BillingMonth, BillingYear, TotalAmount_BeforeDueDate, DueDate, 
                MAX(pd.PaymentStatus) AS PaymentStatus
            FROM 
                Bill b
            LEFT JOIN 
                PaymentDetails pd ON b.BillID = pd.BillID
            WHERE 
                b.ConnectionID = :connection_id
            GROUP BY 
                BillingMonth, BillingYear, TotalAmount_BeforeDueDate, DueDate
            ORDER BY 
                BillingYear DESC, BillingMonth DESC
            FETCH FIRST 10 ROWS ONLY
        """
        cursor.execute(previous_bills_query, [connection_id])
        bills_prev = [
            {
                "month": f"{row[1]}-{row[0]:02d}",
                "amount": float(row[2]),
                "due_date": str(row[3]),
                "status": row[4] if row[4] else "Unpaid",  
            }
            for row in cursor.fetchall()
        ]
    

        connection.close()

    except oracledb.Error as e:
        return templates.TemplateResponse(
            "bill_retrieval.html",  
            {
                "request": request,
                "message": f"Database error: {str(e)}",
                "alert_type": "error",  
                "customer_id": customer_id,
                "connection_id": connection_id,
                "month": month,
                "year": year
            }
        )


    except ValueError as ve:
        return templates.TemplateResponse(
            "bill_retrieval.html",  
            {
                "request": request,
                "message": str(ve),
                "alert_type": "error",
                "customer_id": customer_id,
                "connection_id": connection_id,
                "month": month,
                "year": year
            }
        )




    bill_details = {
        "customer_id": result[0],
        "connection_id": connection_id,  
        "customer_name": result[1],
        "customer_address": result[2],  
        "customer_phone": result[3],  
        "customer_email": result[4],  
        "connection_type": result[5], 
        "division": result[6],  
        "subdivision": result[7],  
        "installation_date": str(result[8]),  
        "meter_type": result[9],  
        "issue_date": str(result[10]), 
        "net_peak_units": result[11], 
        "net_off_peak_units": result[12], 
        "bill_amount": float(result[13]), 
        "due_date": str(result[14]), 
        "amount_after_due_date": float(result[15]), 
        "month": month, 
        "arrears_amount": float(result[16]), 
        "fixed_fee_amount": float(result[17]),  
        "tax_amount": float(result[18]), 
        "tariffs":tariffs,
        "taxes": taxes,
        "subsidies": subsidies, 
        "fixed_fee": fixed_fee,
        "bills_prev": bills_prev,
    }
    
    return templates.TemplateResponse("bill_details.html", {"request": request, "bill_details": bill_details})



@app.post("/bill-adjustments", response_class=HTMLResponse)
async def post_bill_adjustments(
    request: Request,
    bill_id: int = Form(...),
    officer_name: str = Form(...),
    officer_designation: str = Form(...),
    original_bill_amount: float = Form(...),
    adjustment_amount: float = Form(...),
    adjustment_reason: str = Form(...),
):
    try:

        if original_bill_amount - adjustment_amount < 0:
            return templates.TemplateResponse(
            "adjust_bill.html",
            {
                "request": request,
                "message": "Error: The adjustment amount cannot be greater than the original bill amount.",
                "alert_type": "error", 
                "bill_id": bill_id,
                "officer_name": officer_name,
                "officer_designation": officer_designation,
                "original_bill_amount": original_bill_amount,
                "adjustment_amount": adjustment_amount,
                "adjustment_reason": adjustment_reason
            },
        )


        cursor = connection.cursor()

        check_bill_query = """
            SELECT BillID FROM Bill WHERE BillID = :bill_id
        """

        cursor.execute(check_bill_query, {"bill_id": bill_id})
        bill_row = cursor.fetchone()

     
        if bill_row is None:
            return templates.TemplateResponse(
                "adjust_bill.html", 
                {
                    "request": request,
                    "message": f"Error: No bill found with BillID {bill_id}.",  
                    "alert_type": "error", 
                    "bill_id": bill_id,
                    "officer_name": officer_name,
                    "officer_designation": officer_designation,
                    "original_bill_amount": original_bill_amount,
                    "adjustment_amount": adjustment_amount,
                    "adjustment_reason": adjustment_reason
                }
            )








        adjustment_id = str(uuid.uuid4())[:10]  
        check_query = """
            SELECT AdjustmentID FROM BillAdjustments WHERE AdjustmentID = :adjustment_id
        """
        cursor.execute(check_query, {"adjustment_id": adjustment_id})
        while cursor.fetchone():
            adjustment_id = str(uuid.uuid4())[:10] 

     
        adjusted_before_due = original_bill_amount - adjustment_amount
        adjusted_after_due = adjusted_before_due * 1.10  


        bill_update_query = """
            UPDATE Bill
            SET AdjustmentAmount = :adjustment_amount,
                TotalAmount_BeforeDueDate = :adjusted_before_due,
                TotalAmount_AfterDueDate = :adjusted_after_due
            WHERE BillID = :bill_id
        """
        cursor.execute(
            bill_update_query,
            {
                "adjustment_amount": adjustment_amount,
                "adjusted_before_due": adjusted_before_due,
                "adjusted_after_due": adjusted_after_due,
                "bill_id": bill_id,
            },
        )

     
        adjustment_insert_query = """
            INSERT INTO BillAdjustments (
                AdjustmentID, BillID, AdjustmentAmount, AdjustmentReason,
                AdjustmentDate, OfficerName, OfficerDesignation, OriginalBillAmount
            ) VALUES (
                :adjustment_id, :bill_id, :adjustment_amount, :adjustment_reason,
                :adjustment_date, :officer_name, :officer_designation, :original_bill_amount
            )
        """
        cursor.execute(
            adjustment_insert_query,
            {
                "adjustment_id": adjustment_id,
                "bill_id": bill_id,
                "adjustment_amount": adjustment_amount,
                "adjustment_reason": adjustment_reason,
                "adjustment_date": datetime.datetime.now(),
                "officer_name": officer_name,
                "officer_designation": officer_designation,
                "original_bill_amount": original_bill_amount,
            },
        )




       
        connection.commit()

      
        adjustment_details = {
            "adjustment_id": adjustment_id,
            "bill_id": bill_id,
            "officer_name": officer_name,
            "officer_designation": officer_designation,
            "original_bill_amount": original_bill_amount,
            "adjustment_amount": adjustment_amount,
            "adjustment_reason": adjustment_reason,
            "adjustment_date": datetime.datetime.now(),
        }


    except oracledb.Error as e:
        
         return templates.TemplateResponse(
            "adjust_bill.html",
            {
                "request": request,
                "message": f"Error: {str(e)}",
                "alert_type": "error",  
                "bill_id": bill_id,
                "officer_name": officer_name,
                "officer_designation": officer_designation,
                "original_bill_amount": original_bill_amount,
                "adjustment_amount": adjustment_amount,
                "adjustment_reason": adjustment_reason
            },
        )



    return templates.TemplateResponse("adjustment_receipt.html", {"request": request, "adjustment_details": adjustment_details})

if __name__ == "__main__":
    uvicorn.run(app, host='0.0.0.0', port=8000)
