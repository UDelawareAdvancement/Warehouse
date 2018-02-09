   
   /*******************************************************************************************
   -- Create Table Time Dimension
   -- Randy Oswald 7/13/16
   *******************************************************************************************/
   
   -- Create table



create table DW_TIME_DIM (
  datekey                 CHAR(8) not null,
  oracle_date             DATE,
  day_in_month            INTEGER,
  day_in_year             INTEGER,
  fis_day_in_year         INTEGER,
  ytd_ind                 VARCHAR2(1),
  day_text                VARCHAR2(10),
  long_date_text          VARCHAR2(35),
  short_date_text         VARCHAR2(25),
  week_number_in_month    INTEGER,
  cal_week_number_in_year INTEGER,
  fis_week_number_in_year INTEGER,
  overall_week_number     INTEGER,
  cal_month               INTEGER,
  fis_month               INTEGER,
  appraisal_month         INTEGER,
  overall_month_number    INTEGER,
  month_text              VARCHAR2(10),
  cal_decade              VARCHAR2(4),
  fis_decade              VARCHAR2(4),
  cal_year                VARCHAR2(4),
  fis_year                VARCHAR2(4),
  appraisal_year          VARCHAR2(4),
  rel_fis_year            VARCHAR2(4),
  cal_quarter             VARCHAR2(4),
  cal_quarter_text        VARCHAR2(10),
  fis_quarter             VARCHAR2(4),
  fis_quarter_text        VARCHAR2(10),
  weekday                 CHAR(1),
  real_date               CHAR(1),
  campaign                VARCHAR2(20),
  wk_key                  VARCHAR2(8),
  build_date              DATE
);


-- Add Public Synonyms, Grants
--create or replace public synonym  DW_TIME_DIMENSION for UD_ADVANCE.UD_DW_TIME_DIMENSION;     
--grant select on UD_ADVANCE.UD_DW_TIME_DIM to ADV_UD01_ROLE; 
--grant select on UD_ADVANCE.UD_DW_TIME_DIM to ADV_UDADVANCE_SELECTALL;
   
-- Create table
create table STAGE_TIME_DIM (
  datekey                 CHAR(8) not null,
  oracle_date             DATE,
  day_in_month            INTEGER,
  day_in_year             INTEGER,
  fis_day_in_year         INTEGER,
  ytd_ind                 VARCHAR2(1),
  day_text                VARCHAR2(10),
  long_date_text          VARCHAR2(35),
  short_date_text         VARCHAR2(25),
  week_number_in_month    INTEGER,
  cal_week_number_in_year INTEGER,
  fis_week_number_in_year INTEGER,
  overall_week_number     INTEGER,
  cal_month               INTEGER,
  fis_month               INTEGER,
  appraisal_month         INTEGER,
  overall_month_number    INTEGER,
  month_text              VARCHAR2(10),
  cal_decade              VARCHAR2(4),
  fis_decade              VARCHAR2(4),
  cal_year                VARCHAR2(4),
  fis_year                VARCHAR2(4),
  appraisal_year          VARCHAR2(4),
  rel_fis_year            VARCHAR2(4),
  cal_quarter             VARCHAR2(4),
  cal_quarter_text        VARCHAR2(10),
  fis_quarter             VARCHAR2(4),
  fis_quarter_text        VARCHAR2(10),
  weekday                 CHAR(1),
  real_date               CHAR(1),
  campaign                VARCHAR2(20),
  wk_key                  VARCHAR2(8),
  build_date              DATE
)PARTITION BY RANGE(datekey)
    (PARTITION PART_TIME_DIM VALUES LESS THAN (MAXVALUE));

ALTER TABLE STAGE_TIME_DIM MODIFY PARTITION PART_TIME_DIM NOLOGGING;

CREATE UNIQUE INDEX DW_DATE_PK1 ON DW_TIME_DIM (DATEKEY);
create bitmap index TIME_DW_C_YEAR on DW_TIME_DIM (CAL_YEAR);
create bitmap index TIME_DW_DAY_IN_YEAR on DW_TIME_DIM (DAY_IN_YEAR);
create bitmap index TIME_DW_F_DAY_IN_YEAR on DW_TIME_DIM (FIS_DAY_IN_YEAR);
create bitmap index TIME_DW_F_YEAR on DW_TIME_DIM (FIS_YEAR);
create bitmap index DW_TIME_DIM1 on DW_TIME_DIM (OVERALL_WEEK_NUMBER);
create bitmap index DW_TIME_DIM2 on DW_TIME_DIM (OVERALL_MONTH_NUMBER);
create bitmap index DW_TIME_DIM3 on DW_TIME_DIM (CAL_MONTH);
create bitmap index DW_TIME_DIM4 on DW_TIME_DIM (FIS_MONTH);
create bitmap index DW_TIME_DIM5 on DW_TIME_DIM (DAY_IN_MONTH);
create bitmap index DW_TIME_DIM6 on DW_TIME_DIM (WK_KEY);
create bitmap index DW_TIME_DIM7 on DW_TIME_DIM (YTD_IND);
create bitmap index DW_TIME_DIM8 on DW_TIME_DIM (REL_FIS_YEAR);

