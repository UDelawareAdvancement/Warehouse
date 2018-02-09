create or replace package refresh_time_dimension IS


  -- Author  : Randy Oswald
  -- Created : 7/6/16 1:23:34 PM
  -- Purpose : regenerate time dimension daily
  
  function getRelFiscalYear(year_in IN VARCHAR2) return VARCHAR2;
  
  PROCEDURE generate_time_dim;
  
end refresh_time_dimension;
/
create or replace package body refresh_time_dimension IS

   -- Private type declarations
   startYear            CONSTANT INTEGER := 1900;
   endYear              CONSTANT INTEGER := 2100; 

   cur_fis_year         INTEGER;
   fis_year_end_date    DATE;
   
   appraisal_year_month_offset CONSTANT INTEGER := 11;

  function getRelFiscalYear(year_in IN VARCHAR2) return varchar2 is
      year_difference    INTEGER;
      rel_fis_year_output VARCHAR2(10);

  BEGIN
      year_difference := cur_fis_year - year_in;
      IF year_difference >= 0 AND year_difference <= 25 THEN
         rel_fis_year_output := CHR(year_difference + 65);
      ELSIF year_difference >= -9 AND year_difference <= -1 THEN 
         rel_fis_year_output := 'F' || -1 * year_difference;
      ELSE 
         rel_fis_year_output := NULL;
      END IF;
      
      RETURN rel_fis_year_output;
  
  end getRelFiscalYear;



  PROCEDURE generate_time_dim IS

                  
      startDate            DATE;
      dateCounter          DATE;
      endDate              DATE;
                  
      yearCounter          INTEGER := 1;
      monthCounter         INTEGER := 1;
         
      
      fis_year_end_date    DATE;
      cur_fis_day_in_year  INTEGER;
      ytd_month_day_int    INTEGER;
      fis_year_offset      INTEGER;
      
      v_build_date         CONSTANT DATE := SYSDATE;
     -- Testing Edge Cases...
     --v_build_date         CONSTANT DATE := to_date('20160101','YYYYMMDD');
     --v_build_date         CONSTANT DATE := to_date('20160630','YYYYMMDD');
     --v_build_date         CONSTANT DATE := to_date('20160701','YYYYMMDD');
     --v_build_date         CONSTANT DATE := to_date('20161231','YYYYMMDD');
     --v_build_date         CONSTANT DATE := to_date('20170630','YYYYMMDD');
     
      
  BEGIN
     

       
       -- Add 6 hours for warehouse flop, remove one day to not count "today" since gift processing hasn't run yet
       IF v_build_date >= fis_year_end_date THEN 
          ytd_month_day_int := 0699;   -- Move to 99 as a "special value" for End of Fiscal Year Overrun.
       
       -- Edge case for first of fiscal year to prevent backdating from rolling to previous FY. 
       -- This should not usually occur because of the FY overrun (first clause)
       ELSIF to_char(v_build_date,'MMDD') = '0701' THEN
           ytd_month_day_int := 0701;
       ELSE 
          SELECT to_number(to_char(v_build_date + 6/24 - 1, 'MMDD'))
          INTO ytd_month_day_int
          FROM dual;
       END IF;
       
       -- If we are in the second half of the year, add 10,000 to make 0MMDD -> 1MMDD so it "Sorts" higher than first half
       IF ytd_month_day_int BETWEEN 0101 AND 0699THEN 
          ytd_month_day_int := ytd_month_day_int + 10000;
       END IF;          

       startDate := to_date('01-JAN-' || startYear, 'DD-MON-YYYY');
       endDate   := to_date('31-DEC-' || endYear,   'DD-MON-YYYY');

       EXECUTE IMMEDIATE 'truncate TABLE ud_stage_time_dim';
       
       dateCounter := startDate;


       /******************************************************************************
        *    Standard "Real" Dates                                                    *
        ******************************************************************************/

       WHILE dateCounter <= endDate LOOP

         INSERT INTO stage_time_dim VALUES (
                to_char(dateCounter,'YYYYMMDD')                              --date_key
              , dateCounter                                                  --oracle_date
              , to_char(dateCounter,'DD')                                    --day in month
              , to_char(dateCounter,'DDD')                                   --day_in_year
              -- Subtract date of beginning of fiscal year from dateCounter to get number of
              -- days since beginning of fiscal year
              , dateCounter -
                      -- Find beginning of fiscal year for dateCounter
                      -- Subtract 6mo, Trunc to Jan 1, Add 6mo
                      add_months(
                           trunc(
                                add_months(dateCounter,-6)
                           ,'YYYY')
                      ,6) + 1                                                -- fiscal day in year
              , CASE WHEN
                    -- If in second half of the fiscal year, ad 10000 to make a number in the format
                    -- 1MMDD, else it will be 0MMDD.  We can then do a simple numeric comparison.
                    CASE WHEN to_number(to_char(dateCounter, 'MM')) BETWEEN 1 AND 6 THEN 10000 ELSE 0 END
                         + to_number(to_char(dateCounter, 'MMDD')) <= ytd_month_day_int 
                    THEN 'Y'
                    ELSE 'N'
                END                                                          -- YTD_ind
              , to_char(dateCounter,'Day')                                   -- day_text
              , to_char(dateCounter, 'fmDay, Month DD, YYYY')                -- long_date_text
              , to_char(dateCounter, 'FMMM/DD/YYYY')                         -- short_date_text
              , to_char(dateCounter,'W')                                     -- week_number_in_month
              , to_char(dateCounter,'WW')                                    -- cal_week_number_in_year
              , to_char(add_months(dateCounter,6),'WW')                      -- fis_week_number
              , trunc(((dateCounter - startDate) + to_char(startDate,'D') - 1) /7) + 1  --overall_week_number
              , to_char(dateCounter,'MM')                                    -- cal_month
              , to_char(add_months(dateCounter,6),'MM')                      -- fis_month
              , to_char(add_months(dateCounter,appraisal_year_month_offset),'MM')  --appraisal_month
              , ((to_char(dateCounter,'yyyy')-to_char(startDate,'yyyy')) * 12) + to_char(dateCounter,'MM') --overall_month_number
              , to_char(dateCounter,'Month')                                 -- month_text
              , substr(to_char(dateCounter,'YYYY'),1,3)||0                   -- cal_decade
              , substr(to_char(add_months(dateCounter,6),'YYYY'),1,3)||0     -- fis_decade
              , to_char(dateCounter,'YYYY')                                  -- cal_year
              , to_char(add_months(dateCounter,6),'YYYY')                    -- fis_year
              , to_char(add_months(dateCounter,appraisal_year_month_offset),'YYYY')  --appraisal_year
              , getRelFiscalYear(to_char(add_months(dateCounter,6),'YYYY'))  -- rel_fis_year
              , to_char(dateCounter,'Q')                                     -- cal_quarter
              , 'Q' || to_char(dateCounter,'Q YYYY')                         -- cal_quarter_text
              , to_char(add_months(dateCounter,6),'Q')                       -- fis_quarter
              , 'Q' || to_char(add_months(dateCounter,6),'Q YYYY')           -- fis_quarter_text
              , CASE WHEN to_char(dateCounter,'D') = '1' OR to_char(dateCounter,'D') = '7' THEN 'N' ELSE 'Y' END  --weekday
              , 'Y'                                                          -- Real Date
              , ''                                                           -- campaign
              -- Want the 5th week to be week key 5.
              -- How this works: Find the most recent Monday, subract the days since the first Monday of the month, divide by 7 (days of the week) and add one.
              , to_char(next_day(dateCounter-7,'Monday'),'yyyymm') || 'w' ||
                ((
                   (to_char(next_day(dateCounter-7,'Monday'),'DD')  -- most recent Monday (could be today)
                     -to_char(next_day(trunc(next_day(dateCounter-7,'Monday'),'MONTH')-1,'Monday'),'DD') -- first Monday of the month of the most recent Monday (get most recent monday, get that day's month, go back one more day, get the next monday)
                   )/7)+1)
              , v_build_date                                                  -- build date
 
        
         );
        
         dateCounter := dateCounter + 1;
         END LOOP;
         
         /******************************************************************************
         *    Months with no days                                                      *
         ******************************************************************************/
         yearCounter := startYear;
         monthCounter := 1;
         WHILE yearCounter <= endYear LOOP
          
             dateCounter := to_date(lpad(monthCounter,2,'0') || '-01-' || yearCounter, 'MM-DD-YYYY');
             INSERT INTO ud_stage_time_dim VALUES (                     
                      yearCounter || lpad(monthCounter,2,'0') || '00'  --date_key
                    , NULL  --dateCounter  --oracle_date    (Assume 1st of Month) -- [CDS 5/18/2012] Changed to NULL to prevent issues (returns two rows) when joining to time_dim on oracle_date
                    , 0                                          --day in month
                    , to_char(dateCounter,'DDD')                 --day_in_year
                    -- Subtract date of beginning of fiscal year from dateCounter to get number of 
                    -- days since beginning of fiscal year
                    , dateCounter -      
                            -- Find beginning of fiscal year for dateCounter
                            -- Subtract 6mo, Trunc to Jan 1, Add 6mo
                            add_months(  
                                trunc(
                                     add_months(dateCounter,-6)
                                ,'YYYY')
                            ,6) + 1                                -- fiscal day in year
                    , CASE WHEN 
                                -- If in second half of the fiscal year, add 10000 to make a number in the format
                                -- 1MMDD, else it will be 0MMDD.  We can then do a simple numeric comparison.
                                CASE WHEN to_number(to_char(dateCounter, 'MM')) BETWEEN 1 AND 6 THEN 10000 ELSE 0 END
                                + to_number(to_char(dateCounter, 'MMDD'))
                            <= ytd_month_day_int THEN 'Y' 
                            ELSE 'N'
                       END                                           -- YTD_ind
                    , NULL                                           -- day_text
                    , to_char(dateCounter, 'FMMonth YYYY')           -- long_date_text
                    , to_char(dateCounter, 'FMMM/YYYY')              -- short_date_text
                    , 0                                              -- week_number_in_month
                    , to_char(dateCounter,'WW')                      -- cal_week_number_in_year
                    , to_char(add_months(dateCounter,6),'WW')        -- fis_week_number
                    , trunc(((dateCounter - startDate) + to_char(startDate,'D') - 1) /7) + 1  --overall_week_number
                    , to_char(dateCounter,'MM')                      -- cal_month
                    , to_char(add_months(dateCounter,6),'MM')        -- fis_month
                    , to_char(add_months(dateCounter,appraisal_year_month_offset),'MM')  -- appraisal_month
                    , ((to_char(dateCounter,'yyyy')-to_char(startDate,'yyyy')) * 12) + to_char(dateCounter,'MM') --overall_month_number
                    , to_char(dateCounter,'Month')                    -- month_text
                    , substr(to_char(dateCounter,'YYYY'),1,3)||0      -- cal_decade
                    , substr(to_char(add_months(dateCounter,6),'YYYY'),1,3)||0    -- fis_decade
                    , to_char(dateCounter,'YYYY')                     -- cal_year
                    , to_char(add_months(dateCounter,6),'YYYY')       -- fis_year
                    , to_char(add_months(dateCounter,appraisal_year_month_offset),'YYYY')
                    , getRelFiscalYear(to_char(add_months(dateCounter,6),'YYYY'))
                    , to_char(dateCounter,'Q')                        -- cal_quarter
                    , 'Q' || to_char(dateCounter,'Q YYYY')            -- cal_quarter_text
                    , to_char(add_months(dateCounter,6),'Q')          -- fis_quarter
                    , 'Q' || to_char(add_months(dateCounter,6),'Q YYYY') -- fis_quarter_text
                    , 'U'                                             -- weekday
                    , 'N'                                             -- Real Date
                    , ''                                              -- campaign
                    , ''                                              -- week_key
                    , v_build_date                                    -- build date
              );
              monthCounter := mod(monthCounter,12) + 1;   -- Wrap Month
              IF monthCounter = 1 THEN
                   yearCounter := yearCounter + 1; 
              END IF;
         END LOOP;
         
         
         
         /******************************************************************************
         *    Years with no months or days                                                                         *
         ******************************************************************************/
         yearCounter := startYear;
         WHILE yearCounter <= endYear LOOP
          
             dateCounter := to_date( '01-01-' || yearCounter, 'MM-DD-YYYY');
             INSERT INTO stage_time_dim VALUES (
                 yearCounter || '0000'  --date_key
                 , NULL  --dateCounter  --oracle_date    (Assume 1st of Month) -- [CDS 5/18/2012] Changed to NULL to prevent issues (returns two rows) when joining to time_dim on oracle_date
                 , 0                                                 -- day in month
                 , 0                                                 -- day_in_year
                 , 0                                                 -- fis_day_in_year
                 , NULL
                 , NULL                                              -- day_text
                 , yearCounter                                       -- long_date_text
                 , yearCounter                                       -- short_date_text
                 , 0                                                 -- week_number_in_month
                 , 0                                                 -- cal_week_number_in_year
                 , 0                                                 -- fis_week_number
                 , 0                                                 -- epoch_week_number
                 , 0                                                 -- cal_month
                 , 0                                                 -- fis_month
                 , 0                                                 -- appraisal_month
                 , 0                                                 -- epoch_month_number
                 , NULL                                              -- month_text
                 , substr(to_char(dateCounter,'YYYY'),1,3)||0        -- cal_decade
                 , NULL                                              -- fis_decade
                 , yearCounter                                       -- cal_year
                 , NULL                                              -- fis_year
                 , NULL                                              -- appraisal_year
                 , NULL                                              -- rel_fis_year
                 , NULL                                              -- cal_quarter
                 , NULL                                              -- cal_quarter_text
                 , NULL                                              -- fis_quarter
                 , NULL                                              -- fis_quarter_text
                 , 'U'                                               -- weekday
                 , 'N'                                               -- Real Date
                 , ''                                                -- campaign
                 , ''                                                -- week_key
                  , v_build_date                                     -- build date
             );

             yearCounter := yearCounter + 1; 
         END LOOP;
         
           
    /******************************************************************************
    * Now Create Generic Month/Day with blank years                               *
    ******************************************************************************/
       -- Choose an arbitrary year (1967 - it starts on a Sunday)
       startDate := '01-JAN-1967';
       dateCounter := startDate;
       endDate := '31-DEC-1967';

       WHILE dateCounter < endDate LOOP

         INSERT INTO stage_time_dim VALUES (
                  '0000' || to_char(dateCounter,'MMDD')                          -- date_key
                , NULL                                                         -- oracle_date
                , to_char(dateCounter,'DD')                                    -- day in month
                , to_char(dateCounter,'DDD')                                   -- day_in_year
                  -- Subtract date of beginning of fiscal year from dateCounter to get number of
                  -- days since beginning of fiscal year
                , dateCounter -
                      -- Find beginning of fiscal year for dateCounter
                      -- Subtract 6mo, Trunc to Jan 1, Add 6mo
                      add_months(
                          trunc(
                                add_months(dateCounter,-6)
                          ,'YYYY')
                      ,6) + 1                                -- fiscal day in year

                , CASE WHEN
                        -- If in second half of the fiscal year, ad 10000 to make a number in the format
                        -- 1MMDD, else it will be 0MMDD.  We can then do a simple numeric comparison.
                       CASE WHEN to_number(to_char(dateCounter, 'MM')) BETWEEN 1 AND 6 THEN 10000 ELSE 0 END
                             + to_number(to_char(dateCounter, 'MMDD')) <= ytd_month_day_int 
                       THEN 'Y'
                       ELSE 'N'
                  END                                                         -- YTD_ind
                , NULL                                                         -- day_text
                , to_char(dateCounter, 'FMMonth ddth')                         -- long_date_text
                , to_char(dateCounter, 'FMMM/DD')                              -- short_date_text
                , to_char(dateCounter,'W')                                     -- week_number_in_month
                , to_char(dateCounter,'WW')                                    -- cal_week_number_in_year
                , to_char(add_months(dateCounter,6),'WW')                      -- fis_week_number
                , 0                                                            -- epoch_week_number
                , to_char(dateCounter,'MM')                                    -- cal_month
                , to_char(add_months(dateCounter,6),'MM')                            --fis_month
                , to_char(add_months(dateCounter,appraisal_year_month_offset),'MM')  --appraisal_month
                , 0                                                            -- epoch_month_number
                , to_char(dateCounter,'Month')                                 -- month_text
                , NULL                                                         -- cal_decade
                , NULL                                                         -- fis_decade
                , NULL                                                         -- cal_year
                , NULL                                                         -- fis_year
                , NULL                                                         -- appraisal_year
                , NULL                                                         -- rel_fis_year
                , to_char(dateCounter,'Q')                                     -- cal_quarter
                , 'Q' || to_char(dateCounter,'Q')                              -- cal_quarter_text
                , to_char(add_months(dateCounter,6),'Q')                       -- fis_quarter
                , 'Q' || to_char(add_months(dateCounter,6),'Q')                -- fis_quarter_text
                , 'U'                                                          -- weekday
                , 'N'                                                          -- Real Date
                , NULL                                                         -- campaign
                , ''                                                           -- week_key
                , v_build_date                                                 -- build date
              );

         dateCounter := dateCounter + 1;
         END LOOP;

         
         /******************************************************************************
         *    Months with no days or years                                             *
         ******************************************************************************/
         yearCounter := 1967;
         monthCounter := 1;
         WHILE monthCounter <= 12 LOOP
          
             dateCounter := to_date(monthCounter || '-01-' || yearCounter, 'MM-DD-YYYY');
             INSERT INTO stage_time_dim VALUES (
                  '0000' || lpad(monthCounter,2,'0') || '00'    --date_key
                 , NULL                                --oracle_date    (Assume 1st of Month
                 , 0                                          --day in month
                 , to_char(dateCounter,'DDD')                 --day_in_year
                   -- Subtract date of beginning of fiscal year from dateCounter to get number of
                   -- days since beginning of fiscal year
                 , dateCounter -
                         -- Find beginning of fiscal year for dateCounter
                         -- Subtract 6mo, Trunc to Jan 1, Add 6mo
                         add_months(
                             trunc(
                                  add_months(dateCounter,-6)
                             ,'YYYY')
                         ,6) + 1                                     --fiscal day in year
                 , CASE WHEN
                        -- If in second half of the fiscal year, ad 10000 to make a number in the format
                        -- 1MMDD, else it will be 0MMDD.  We can then do a simple numeric comparison.
                        CASE WHEN to_number(to_char(dateCounter, 'MM')) BETWEEN 1 AND 6 THEN 10000 ELSE 0 END
                             + to_number(to_char(dateCounter, 'MMDD')) <= ytd_month_day_int 
                        THEN 'Y'
                        ELSE 'N'
                   END                                               -- YTD_ind
                 , NULL                                              -- day_text
                 , to_char(dateCounter,'FMMonth')                    -- long_date_text
                 , to_char(dateCounter,'FMMon')                      -- short_date_text
                 , to_char(dateCounter,'W')                          -- week_number_in_month
                 , to_char(dateCounter,'WW')                         -- cal_week_number_in_year
                 , to_char(add_months(dateCounter,6),'WW')           -- fis_week_number
                 , 0                                                 -- epoch_week_number
                 , to_char(dateCounter,'MM')                         -- cal_month
                 , to_char(add_months(dateCounter,6),'MM')           -- fis_month
                 , to_char(add_months(dateCounter,appraisal_year_month_offset),'MM')  --appraisal_month
                 , 0                                                 -- epoch_month_number
                 , to_char(dateCounter,'Month')                      -- month_text
                 , NULL                                              -- cal_decade
                 , NULL                                              -- fis_decade
                 , NULL                                              -- cal_year
                 , NULL                                              -- fis_year
                 , NULL                                              -- appraisal_year
                 , NULL                                              -- rel_fis_year
                 , to_char(dateCounter,'Q')                          -- cal_quarter
                 , 'Q' || to_char(dateCounter,'Q')                   -- cal_quarter_text
                 , to_char(add_months(dateCounter,6),'Q')            -- fis_quarter
                 , 'Q' || to_char(add_months(dateCounter,6),'Q')     -- fis_quarter_text
                 , 'U'                                               -- weekday
                 , 'N'                                               -- Real Date
                 , NULL                                              -- campaign
                 , ''                                                -- week_key
                 , v_build_date                                      -- build date
                 );
             monthCounter := monthCounter + 1;   -- Wrap Month
         END LOOP;
         
         /******************************************************************************
         *    Insert Unknown value: 00000000                                           *
         ******************************************************************************/
         INSERT INTO stage_time_dim VALUES (                     
                  '00000000'                                        -- date_key
                , NULL                                              -- oracle_date
                , 0                                                 -- day in month
                , 0                                                 -- day_in_year
                , 0                                                 -- fis_day_in_year
                , NULL                                              -- ytd_ind
                , NULL                                              -- day_text
                , NULL                                              -- long_date_text
                , NULL                                              -- short_date_text
                , 0                                                 -- week_number_in_month
                , 0                                                 -- cal_week_number_in_year
                , 0                                                 -- fis_week_number
                , 0                                                 -- epoch_week_number
                , 0                                                 -- cal_month
                , 0                                                 -- fis_month
                , 0                                                 -- appraisal_month
                , 0                                                 -- epoch_month_number
                , NULL                                              -- month_text
                , NULL                                              -- cal_decade
                , NULL                                              -- fis_decade
                , NULL                                              -- cal_year
                , NULL                                              -- fis_year
                , NULL                                              -- appraisal_year
                , NULL                                              -- rel_fis_year
                , NULL                                              -- cal_quarter
                , NULL                                              -- cal_quarter_text
                , NULL                                              -- fis_quarter
                , NULL                                              -- fis_quarter_text
                , 'U'                                               -- weekday
                , 'N'                                               -- Real Date
                , NULL                                              -- campaign
                , ''                                                -- week_key
                , v_build_date                                      -- build date
         );
         
         INSERT INTO stage_time_dim VALUES (                     
                  '99999999'                                         --date_key
                , NULL                                              --oracle_date
                , 0                                                 --day in month
                , 0                                                 --day_in_year
                , 0                                                 --fis_day_in_year
                , NULL                                              -- ytd_ind
                , NULL                                              --day_text
                , NULL                                              --long_date_text
                , NULL                                              --short_date_text
                , 0                                                 --week_number_in_month
                , 0                                                 --cal_week_number_in_year
                , 0                                                 --fis_week_number
                , 0                                                 --epoch_week_number
                , 0                                                 --cal_month
                , 0                                                 --fis_month
                , 0                                                 --appraisal_month
                , 0                                                 --epoch_month_number
                , NULL                                              --month_text
                , NULL                                              --cal_decade
                , NULL                                              --fis_decade
                , NULL                                              --cal_year
                , NULL                                              --fis_year
                , NULL                                              --appraisal_year
                , NULL                                              --rel_fis_year
                , NULL                                              --cal_quarter
                , NULL                                              --cal_quarter_text
                , NULL                                              --fis_quarter
                , NULL                                              --fis_quarter_text
                , 'U'                                               --weekday
                , 'N'                                               --Real Date
                , NULL                                              --campaign
                , ''                                                -- week_key
                , v_build_date                                      --build date
                );
         COMMIT WORK;
  
END generate_time_dim;


BEGIN
  /**
  * Initialization
  */
   SELECT fy.fy_a
          , to_date(fy.fy_a_end_date,'YYYYMMDD')
   INTO   cur_fis_year
          , fis_year_end_date
   FROM ud_fyears fy;

end refresh_time_dimension;
/
