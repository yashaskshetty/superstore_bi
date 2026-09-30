-- ============================================================
-- 00a_reset_schema.sql   run as: superstore/superstore
-- Idempotent teardown. Makes 01_tables.sql and 05_views_indexes.sql
-- safe to re-run on an existing schema instead of failing with
-- ORA-00955 (name is already used by an existing object).
--
-- Preferred over dropping the whole user, which fails with
-- ORA-01940 whenever any session still holds the schema.
-- ============================================================
set serveroutput on feedback off

DECLARE
  PROCEDURE drop_obj (p_type VARCHAR2, p_name VARCHAR2) IS
  BEGIN
    IF p_type = 'TABLE' THEN
      EXECUTE IMMEDIATE 'DROP TABLE '||p_name||' CASCADE CONSTRAINTS PURGE';
    ELSE
      EXECUTE IMMEDIATE 'DROP '||p_type||' '||p_name;
    END IF;
    DBMS_OUTPUT.PUT_LINE('dropped '||LOWER(p_type)||' '||LOWER(p_name));
  EXCEPTION
    WHEN OTHERS THEN
      -- ORA-00942 table/view, -04043 object, -02289 sequence, -01418 index, -01434 synonym
      IF SQLCODE IN (-942, -4043, -2289, -1418, -1434) THEN NULL;
      ELSE RAISE;
      END IF;
  END drop_obj;
BEGIN
  -- views first (they depend on the package and tables)
  FOR v IN (SELECT view_name FROM user_views) LOOP
    drop_obj('VIEW', v.view_name);
  END LOOP;

  FOR s IN (SELECT synonym_name FROM user_synonyms) LOOP
    drop_obj('SYNONYM', s.synonym_name);
  END LOOP;

  FOR p IN (SELECT object_name, object_type FROM user_objects
             WHERE object_type IN ('PACKAGE','PROCEDURE','FUNCTION')) LOOP
    drop_obj(p.object_type, p.object_name);
  END LOOP;

  -- fact before dimensions; CASCADE CONSTRAINTS covers any ordering surprise
  FOR t IN (SELECT table_name FROM user_tables
             ORDER BY CASE WHEN table_name LIKE 'FACT%' THEN 0
                           WHEN table_name LIKE 'ERR$%' THEN 1 ELSE 2 END) LOOP
    drop_obj('TABLE', t.table_name);
  END LOOP;

  FOR q IN (SELECT sequence_name FROM user_sequences) LOOP
    drop_obj('SEQUENCE', q.sequence_name);
  END LOOP;

  -- indexes not already removed with their tables
  FOR i IN (SELECT index_name FROM user_indexes WHERE index_name NOT LIKE 'SYS_%') LOOP
    drop_obj('INDEX', i.index_name);
  END LOOP;
END;
/

prompt --- objects remaining (should be none) ---
SELECT object_type, COUNT(*) FROM user_objects GROUP BY object_type ORDER BY 1;
exit
