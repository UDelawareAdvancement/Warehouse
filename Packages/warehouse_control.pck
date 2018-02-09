CREATE OR REPLACE PACKAGE WAREHOUSE_CONTROL IS

  -- Author  : DOLPHIO
  -- Created : 2/13/2009 2:21:25 PM
  -- Purpose : Maintain Warehouse Tables
  
  
PROCEDURE drop_table_indexes(
  p_table_name         VARCHAR2
);
  
PROCEDURE create_stage_tbl_index_from_dw(
  p_dw_table_name   VARCHAR2
);

PROCEDURE refresh_generic_dw_table(
   p_dw_tbl_name       VARCHAR2
  ,p_bldr_view_name    VARCHAR2
);

 PROCEDURE REFRESH_TIME_DIMENSION;


  END WAREHOUSE_CONTROL;
/
CREATE OR REPLACE PACKAGE BODY WAREHOUSE_CONTROL IS

   -- Declare exception to handle dropping of non-existant indexes.  Throw warning
   NO_INDEX_TO_DROP EXCEPTION;

   PRAGMA EXCEPTION_INIT(NO_INDEX_TO_DROP, -1418);

   NO_CONSTRAINT_TO_DROP EXCEPTION;

   PRAGMA EXCEPTION_INIT(NO_CONSTRAINT_TO_DROP, -2443);

   c_package_name    VARCHAR2(20) := 'ud_warehouse';


FUNCTION get_table_index_create_stmts(
  p_dw_table_name         VARCHAR2
)
RETURN ud_db_utils.string_arr_type
IS 

  v_index_arr         ud_db_utils.string_arr_type;
  v_index_dml_arr     ud_db_utils.string_arr_type;
  v_dml_string        VARCHAR2(2000);
  v_index_create_arr  ud_db_utils.string_arr_type;
  v_index_create_counter INTEGER;

BEGIN
  
  SELECT t.INDEX_NAME
  BULK COLLECT INTO v_index_arr
  FROM all_indexes t
  WHERE t.TABLE_NAME = upper(p_dw_table_name);

  v_index_create_counter := 0;

  -- loop on all indexes on the table
  FOR indx_name_counter IN v_index_arr.first .. v_index_arr.last
    LOOP

    --ud_log.log_info('index name is ' || v_index_arr(indx_name_counter));

    SELECT DBMS_METADATA.GET_DDL('INDEX',v_index_arr(indx_name_counter))
    INTO v_dml_string
    FROM DUAL;

    v_index_dml_arr := ud_db_utils.split_string_to_array(v_dml_string,chr(10));
   
    -- loop through DML to get the create statement and add it to v_index_create_arr 
    FOR indx IN v_index_dml_arr.FIRST .. v_index_dml_arr.LAST
      LOOP

      v_dml_string := trim(v_index_dml_arr(indx));
      
      IF substr(v_dml_string,0,6) = 'CREATE' THEN
        --ud_log.log_info('index dml line ' || v_index_dml_arr(indx));
        v_index_create_arr(v_index_create_counter) := v_dml_string;
        v_index_create_counter := v_index_create_counter + 1;
      END IF;

    END LOOP;
  END LOOP;

  RETURN v_index_create_arr;

END get_table_index_create_stmts;


PROCEDURE create_stage_tbl_index_from_dw(
  p_dw_table_name   VARCHAR2
)
IS
  
  v_index_create_arr        ud_db_utils.string_arr_type;
  v_dw_create_string        VARCHAR2(500);
  v_stage_create_string     VARCHAR2(500);
  
BEGIN
  
  ud_log.log_info('Creating indexes');

  v_index_create_arr := get_table_index_create_stmts(p_dw_table_name);

  FOR indx IN v_index_create_arr.first .. v_index_create_arr.last 
    LOOP
      
    v_dw_create_string := v_index_create_arr(indx);
    v_stage_create_string := REPLACE(v_dw_create_string,'_DW_','_ST_');
    ud_log.log_info('stage index create is ' || v_stage_create_string);
    EXECUTE IMMEDIATE v_stage_create_string || ' local';
    
  END LOOP;

END;


PROCEDURE drop_indexes(
  p_index_arr         ud_varray
)
IS 
BEGIN
  
  ud_log.log_info('Dropping indexes');

  IF p_index_arr.count > 0 THEN

    FOR indx IN p_index_arr.FIRST .. p_index_arr.LAST
      LOOP
      
      BEGIN
        EXECUTE IMMEDIATE 'DROP INDEX ' || p_index_arr(indx);
      EXCEPTION
        WHEN NO_INDEX_TO_DROP THEN
          ud_log.log_warning(p_custom_msg_1 => 'Could not drop index ' || p_index_arr(indx));
      END;

    END LOOP;
  
  END IF;

END drop_indexes;


PROCEDURE drop_table_indexes(
  p_table_name   VARCHAR2
)
IS

  v_index_arr  ud_varray;

BEGIN
  
  ud_log.log_info(p_custom_msg_1 => 'Dropping indexes from ' || p_table_name);

  SELECT t.INDEX_NAME
  BULK COLLECT INTO v_index_arr
  FROM all_indexes t
  WHERE t.TABLE_NAME = upper(p_table_name);

  drop_indexes(v_index_arr);

END;

PROCEDURE refresh_generic_dw_table(
   p_dw_tbl_name       VARCHAR2
  ,p_bldr_view_name    VARCHAR2
)
IS

  v_job_name  VARCHAR2(100);
  V_ROW_COUNT INTEGER := 0;
  v_dw_tbl_name       VARCHAR2(32) := upper(p_dw_tbl_name);
  v_stage_tbl_name    VARCHAR2(32) := REPLACE(upper(p_dw_tbl_name),'_DW_','_ST_');
  v_part_tbl_name     VARCHAR2(32) := REPLACE(upper(p_dw_tbl_name),'_DW_','_PT_');
  v_bldr_name         VARCHAR2(32) := upper(p_bldr_view_name);

BEGIN
  
  v_job_name := c_package_name || '.refresh_' || substr(v_dw_tbl_name,7);

  ud_log.begin_log(p_name_pkg_proc_func => v_job_name);
  drop_table_indexes(p_table_name => v_stage_tbl_name);

  ud_log.log_info(p_custom_msg_1 => 'Truncating table');
  EXECUTE IMMEDIATE 'truncate table ' || v_stage_tbl_name;

  ud_log.log_info(p_custom_msg_1 => 'Inserting rows');
        
  -- Use append hint to direct-load (no logging) 
  EXECUTE IMMEDIATE 'INSERT /*+ APPEND */ INTO ' || v_stage_tbl_name || 
  ' SELECT * FROM ' || p_bldr_view_name;
              
  V_ROW_COUNT := SQL%ROWCOUNT;
  COMMIT;
        
  create_stage_tbl_index_from_dw(p_dw_table_name => v_dw_tbl_name);

  EXECUTE IMMEDIATE 'ALTER TABLE ' || v_stage_tbl_name ||
       ' exchange partition ' || v_part_tbl_name ||
       ' with table ' || v_dw_tbl_name || 
       ' including indexes
         without validation';
             
  DBMS_STATS.GATHER_TABLE_STATS('ud_advance', v_dw_tbl_name);
        
  EXECUTE IMMEDIATE 'TRUNCATE TABLE ' || v_stage_tbl_name;
  
  ud_log.end_log(p_name_pkg_proc_func => v_job_name, p_total_rows => V_ROW_COUNT);
        
EXCEPTION
  WHEN OTHERS THEN
     ud_log.log_error(p_custom_msg_1 =>  'Failed refreshing ' || v_dw_tbl_name);
END;




   /*******************************************************************************************
   -- Refresh Time Dimension
   -- Randy Oswald 7/13/16
   *******************************************************************************************/
   PROCEDURE REFRESH_TIME_DIMENSION IS
      V_ROW_COUNT INTEGER := 0;
   BEGIN
      ud_log.begin_log;
      
      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX TIME_STAGE_DATE_PK';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index TIME_STAGE_DATE_PK');
      END;

      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX TIME_STAGE_C_YEAR';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index TIME_STAGE_C_YEAR');
      END;

      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX TIME_STAGE_DAY_IN_YEAR';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index TIME_STAGE_DAY_IN_YEAR');
      END;

      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX TIME_STAGE_F_DAY_IN_YEAR';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index TIME_STAGE_F_DAY_IN_YEAR');
      END;

      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX TIME_STAGE_F_YEAR';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index TIME_STAGE_F_YEAR');
      END;

      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX STAGE_TIME_DIM1';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index STAGE_TIME_DIM1');
      END;
      
      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX STAGE_TIME_DIM2';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index STAGE_TIME_DIM2');
      END;
      
      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX STAGE_TIME_DIM3';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index STAGE_TIME_DIM3');
      END;
      
      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX STAGE_TIME_DIM4';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index STAGE_TIME_DIM4');
      END;
      
      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX STAGE_TIME_DIM5';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index STAGE_TIME_DIM5');
      END;
      
      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX STAGE_TIME_DIM6';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index STAGE_TIME_DIM6');
      END;
      
      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX STAGE_TIME_DIM7';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index STAGE_TIME_DIM7');
      END;
      
      BEGIN
         EXECUTE IMMEDIATE 'drop INDEX STAGE_TIME_DIM8';
      EXCEPTION
         WHEN NO_INDEX_TO_DROP THEN
            ud_log.log_warning(p_custom_msg_1 => 'Could not drop index STAGE_TIME_DIM8');
      END;
         
      EXECUTE IMMEDIATE 'truncate table STAGE_TIME_DIM';
      -- Use append hint to direct-load (no logging) 
      ud_bldr_refresh_time_dimension.generate_time_dim;
      

      V_ROW_COUNT := SQL%ROWCOUNT;
      COMMIT;

      EXECUTE IMMEDIATE 'CREATE UNIQUE INDEX TIME_STAGE_DATE_PK ON STAGE_TIME_DIM (DATEKEY) local compute statistics';
      execute immediate 'create bitmap index TIME_STAGE_C_YEAR on STAGE_TIME_DIM (CAL_YEAR) local compute statistics';
      execute immediate 'create bitmap index TIME_STAGE_DAY_IN_YEAR on STAGE_TIME_DIM (DAY_IN_YEAR) local compute statistics';
      execute immediate 'create bitmap index TIME_STAGE_F_DAY_IN_YEAR on STAGE_TIME_DIM (FIS_DAY_IN_YEAR) local compute statistics';
      execute immediate 'create bitmap index TIME_STAGE_F_YEAR on STAGE_TIME_DIM (FIS_YEAR) local compute statistics';
      execute immediate 'create bitmap index STAGE_TIME_DIM1 on STAGE_TIME_DIM (OVERALL_WEEK_NUMBER) local compute statistics';
      execute immediate 'create bitmap index STAGE_TIME_DIM2 on STAGE_TIME_DIM (OVERALL_MONTH_NUMBER) local compute statistics';
      execute immediate 'create bitmap index STAGE_TIME_DIM3 on STAGE_TIME_DIM (CAL_MONTH) local compute statistics';
      execute immediate 'create bitmap index STAGE_TIME_DIM4 on STAGE_TIME_DIM (FIS_MONTH) local compute statistics';
      execute immediate 'create bitmap index STAGE_TIME_DIM5 on STAGE_TIME_DIM (DAY_IN_MONTH) local compute statistics';
      execute immediate 'create bitmap index STAGE_TIME_DIM6 on STAGE_TIME_DIM (WK_KEY) local compute statistics';
      execute immediate 'create bitmap index STAGE_TIME_DIM7 on STAGE_TIME_DIM (YTD_IND) local compute statistics';
      execute immediate 'create bitmap index STAGE_TIME_DIM8 on STAGE_TIME_DIM (REL_FIS_YEAR) local compute statistics';
      

      EXECUTE IMMEDIATE 'ALTER TABLE STAGE_TIME_DIM
           exchange partition PART_TIME_DIM
           with table DW_TIME_DIM
           including indexes
           without validation';
      DBMS_STATS.GATHER_TABLE_STATS('ud_advance', 'DW_TIME_DIM', CASCADE => TRUE);
      EXECUTE IMMEDIATE 'truncate table STAGE_TIME_DIM';
      ud_log.end_log(p_total_rows => v_row_count);
   EXCEPTION
      WHEN OTHERS THEN
         ud_log.log_error(p_custom_msg_1 =>  'Failed refreshing Time Dimension Table');
   END REFRESH_TIME_DIMENSION;
   
   
   
    
END WAREHOUSE_CONTROL;
/
