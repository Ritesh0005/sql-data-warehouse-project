CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	DECLARE @start_time DATETIME,@end_time DATETIME,@batch_start_time DATETIME,@batch_end_time DATETIME;
	SET @batch_start_time = GETDATE();
	BEGIN TRY
	print'====================================================';
	print'Loading Silver Layer';
	print'====================================================';

	print'----------------------------------------------------';
	print'Loading CRM Tables';
	print'----------------------------------------------------';

	--loading silver.crm_cust_info
	SET @start_time = GETDATE();
	print'>>Truncating table :silver.crm_cust_info';
	TRUNCATE TABLE silver.crm_cust_info;

	print '>>Inserting Data Into: silver.crm_cust_info';
	INSERT INTO silver.crm_cust_info (
		 cst_id,
		 cst_key,
		 cst_firstname,
		 cst_lastname,
		 cst_marital_status,
		 cst_gndr,
		 cst_create_date 
		 )
	select
		cst_id,
		cst_key,
		trim(cst_firstname) as cst_firstname,
		trim(cst_lastname)as cst_lastname,
		CASE 
			WHEN UPPER(TRIM(cst_marital_status)) ='S' THEN 'Single'
			WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
			ELSE 'N/A'
		END AS cst_marital_status,--Normalize martial status values to readable format
		CASE 
			WHEN UPPER(TRIM(cst_gndr)) ='F' THEN 'Female'
			WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
			ELSE 'N/A'
		END AS cst_gndr,--Normalize gender values to readable format
		cst_create_date
	from (SELECT 
		*,
		ROW_NUMBER() OVER(PARTITION BY cst_id order by cst_create_date desc) as flag_last
		FROM bronze.crm_cust_info
		WHERE cst_id IS NOT NULL
	)t where flag_last = 1;-- Select the most recent record per customer
	SET @end_time = GETDATE();
	
	PRINT'>>LOAD DURATION:' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + 'sec';
	PRINT'________________________________';

	print'============================================================================================';
	
	--loading silver.crm_prd_info	
	SET @start_time = GETDATE();
	print'>>Truncating table :silver.crm_prd_info';
	TRUNCATE TABLE silver.crm_prd_info;

	print '>>Inserting Data Into: silver.crm_prd_info';
	insert into silver.crm_prd_info(
	prd_id,
	cat_id,
	prd_key,
	prd_nm,
	prd_cost,
	prd_line,
	prd_start_dt,
	prd_end_dt)
	select 
		prd_id,
		replace(SUBSTRING(prd_key,1,5),'-','_') as cat_id,--Extract category ID
		SUBSTRING(prd_key,7,len(prd_key)) as prd_key,--Extract product key
		prd_nm,
		coalesce(prd_cost,0) as prd_cost,--replacing the nulls
		CASE UPPER(TRIM(prd_line))
			WHEN  'M' THEN 'Mountain'
			WHEN  'R' THEN 'Road'
			WHEN  'S' THEN 'Other Sales'
			WHEN  'T' THEN 'Touring'
			ELSE 'N/A'
		END as prd_line,--Map product line codes to descriptive values
		cast(prd_start_dt as date) as prd_start_dt,
		cast(
			lead(prd_start_dt) over(partition by prd_key order by prd_start_dt)-1
			as date
			) as prd_end_dt-- Calculate end date as one day before the next start date
	from bronze.crm_prd_info
	SET @end_time = GETDATE();
	
	PRINT'>>LOAD DURATION :' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR)+ 'sec';
	PRINT'________________________________';



	print'============================================================================================';
	
	--loading silver.crm_sales_details
	SET @start_time = GETDATE();
	print'>>Truncating table :silver.crm_sales_details';
	TRUNCATE TABLE silver.crm_sales_details;

	print '>>Inserting Data Into: silver.crm_sales_details';
	insert into silver.crm_sales_details(
	sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	sls_order_dt,
	sls_ship_dt,
	sls_due_dt,
	sls_sales,
	sls_quantity,
	sls_price
	)
	select sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	case 
		when sls_order_dt <= 0 OR LEN(sls_order_dt) != 8 then null
		else cast(cast(sls_order_dt as varchar) as date) 
	end as sls_order_dt,	
	case 
		when sls_ship_dt <= 0 OR LEN(sls_ship_dt) != 8 then null
		else cast(cast(sls_ship_dt as varchar) as date) 
	end as sls_ship_dt,
	case 
		when sls_due_dt <= 0 OR LEN(sls_due_dt) != 8 then null
		else cast(cast(sls_due_dt as varchar) as date) 
	end as sls_due_dt,
	CASE
		WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * abs(sls_price)
		THEN sls_quantity * abs(sls_price)
		else sls_sales
	END AS sls_sales ,--Recalculate sales  if original value is missing or incorrect
	sls_quantity,
	CASE
		WHEN sls_price IS NULL OR sls_price <= 0
		THEN sls_sales/NULLIF(sls_quantity,0)
		ELSE sls_price--Derive price if original value is missing or incorrect
	END as sls_price
	from bronze.crm_sales_details 
	SET @end_time = GETDATE();
	
	PRINT'>>LOAD DURATION:' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR )+ 'sec';
	PRINT'________________________________';


	print'============================================================================================';
	--loading silver.erp_cust_az12
	SET @start_time = GETDATE();
	print'>>Truncating table :silver.erp_cust_az12';
	TRUNCATE TABLE silver.erp_cust_az12;

	print '>>Inserting Data Into: silver.erp_cust_az12';
	insert into silver.erp_cust_az12(
	cid,
	bdate,
	gen)
	select
	case when upper(LEFT(cid,3)) = 'NAS' then trim(REPLACE(cid,'NAS',''))-- Remove 'NAS' prefix if present
		else cid
	end as cid,
	case 
		when bdate > getdate() then NULL
		else bdate
	end as bdate,--Set future birthdates to null
	case	
		when upper(trim(gen)) in ('F','FEMALE') then 'Female'
		when upper(trim(gen)) in ('M','MALE') then 'Male'
		else 'N/A'
	end as gen--Normalize gender values and handle unknown cases
	from bronze.erp_cust_az12
	SET @end_time = GETDATE();
	
	PRINT'>>LOAD DURATION:' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR)+ 'sec';
	PRINT'________________________________';

	print'============================================================================================';
	--loading silver.erp_loc_a101
	SET @start_time = GETDATE();
	print'>>Truncating table :silver.erp_loc_a101';
	TRUNCATE TABLE silver.erp_loc_a101;

	print '>>Inserting Data Into: silver.erp_loc_a101';
	insert into silver.erp_loc_a101
	(cid,cntry)
	select 
	replace(cid,'-','') as cid,--handled invalid values
	CASE
		when trim(cntry) = 'DE' then 'Germany'
		when trim(cntry) in ('US','USA') then 'United States'
		when trim(cntry) = '' or cntry IS NULL then 'N/A'
		Else cntry
	END as cntry--Normalize and Handle missing or blank country codes
	from bronze.erp_loc_a101
	SET @end_time = GETDATE();
	
	PRINT'>>LOAD DURATION:' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR)+ 'sec';
	PRINT'________________________________';

	
	print'============================================================================================';
	
	--loading silver.erp_cust_az12
	SET @start_time = GETDATE();
	print'>>Truncating table :silver.erp_px_cat_g1v2';
	TRUNCATE TABLE silver.erp_px_cat_g1v2;
	print '>>Inserting Data Into: silver.erp_px_cat_g1v2';
	insert into silver.erp_px_cat_g1v2(
	id,
	cat,
	subcat,
	maintenance)
	select id,
	cat,
	subcat,
	maintenance
	from bronze.erp_px_cat_g1v2
	SET @end_time = GETDATE();
	
	PRINT'>>LOAD DURATION:' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR)+ 'sec';
	PRINT'________________________________';


	END TRY
	
	BEGIN CATCH
		PRINT'=======================================================';
		PRINT'ERROR MESSAGE OCCURED DURING LOADING OF BRONZE LAYER';
		PRINT'ERROR MESSAGE:' + ERROR_MESSAGE();
		PRINT'ERROR MESSAGE:' + CAST(ERROR_NUMBER() AS NVARCHAR);
		PRINT'ERROR MESSAGE:' + CAST(ERROR_STATE() AS NVARCHAR);
		PRINT'=======================================================';
	END CATCH
	SET @batch_end_time = GETDATE();
	PRINT'DONE LOADING SILVER LAYER';
	PRINT'>>DURATION OF LOADING SILVER LAYER:'  +CAST(DATEDIFF(SECOND,@batch_start_time,@batch_end_time)AS NVARCHAR)+ 'sec';


END






