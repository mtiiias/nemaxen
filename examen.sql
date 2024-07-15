CREATE OR REPLACE PACKAGE pkg_postulacion IS
v_rutina_bug VARCHAR(350);
v_message_bug VARCHAR(350);
v_numrun NUMBER;
v_puntaje NUMBER;
FUNCTION fn_obt_ptje_zona_extrema(pa_zonaextrema NUMBER) RETURN NUMBER;
FUNCTION fn_obt_ptje_rank_insti(pa_rank NUMBER) RETURN NUMBER;
END;

/

CREATE OR REPLACE PACKAGE BODY pkg_postulacion IS
FUNCTION fn_obt_ptje_zona_extrema(pa_zonaextrema NUMBER) RETURN NUMBER
IS
BEGIN
SELECT PTJE_ZONA INTO pkg_postulacion.v_puntaje
FROM PTJE_ZONA_EXTREMA WHERE ZONA_EXTREMA = pa_zonaextrema;
RETURN pkg_postulacion.v_puntaje;
END;
FUNCTION fn_obt_ptje_rank_insti(pa_rank NUMBER) RETURN NUMBER IS
BEGIN
SELECT PTJE_RANKING INTO pkg_postulacion.v_puntaje FROM PTJE_RANKING_INST 
WHERE pa_rank BETWEEN RANGO_RANKING_INI AND RANGO_RANKING_TER;
RETURN pkg_postulacion.v_puntaje;
END; 
END;

/

CREATE OR REPLACE PROCEDURE procedure_save_bug(pa_numrun NUMBER, pa_rutina_bug VARCHAR2, p_menssage_bug VARCHAR2) IS
BEGIN
INSERT INTO ERROR_PROCESO VALUES(pa_numrun, pa_rutina_bug , p_menssage_bug);
END;

/

CREATE OR REPLACE FUNCTION fn_obt_ptje_horas_trab(pa_hour NUMBER) RETURN NUMBER IS
BEGIN
SELECT PTJE_HORAS_TRAB INTO pkg_postulacion.v_puntaje FROM PTJE_HORAS_TRABAJO 
WHERE pa_hour BETWEEN RANGO_HORAS_INI AND RANGO_HORAS_TER;    
RETURN pkg_postulacion.v_puntaje;
EXCEPTION  WHEN OTHERS THEN
pkg_postulacion.v_rutina_bug := 'Error en la FN_OBT_PTJE_HORAS_TRAB al obtener puntaje con horas de trabajo semanal: ' || pa_hour;
pkg_postulacion.v_message_bug := SQLERRM;
procedure_save_bug(pkg_postulacion.v_numrun, pkg_postulacion.v_rutina_bug , pkg_postulacion.v_message_bug);
RETURN 0;
END;

/

CREATE OR REPLACE FUNCTION fn_obt_ptje_annos_experiencia(pa_age NUMBER) RETURN NUMBER IS
BEGIN
SELECT PTJE_EXPERIENCIA INTO pkg_postulacion.v_puntaje FROM PTJE_ANNOS_EXPERIENCIA 
WHERE pa_age BETWEEN RANGO_ANNOS_INI AND RANGO_ANNOS_TER;
RETURN pkg_postulacion.v_puntaje;
EXCEPTION WHEN OTHERS THEN
pkg_postulacion.v_rutina_bug := 'Error en la FN_OBT_PTJE_ANNOS_EXPERIENCIA al obtener puntaje con años de experiencia: ' || pa_age;
pkg_postulacion.v_message_bug := SQLERRM;
procedure_save_bug(pkg_postulacion.v_numrun, pkg_postulacion.v_rutina_bug, pkg_postulacion.v_message_bug);
RETURN 0;
END;

/

CREATE OR REPLACE PROCEDURE procedure_process_post(pa_date VARCHAR2, pa_extra1 NUMBER, pa_extra2 NUMBER) IS  
v_year_contract NUMBER;
v_hour_work NUMBER;
v_zonaExtrema NUMBER;
v_ptje_xp NUMBER;
v_ptje_hour NUMBER;
v_ptje_zonaExtrema NUMBER;
v_ptje_rank_ins NUMBER;
v_ptje_extra1 NUMBER;
v_ptje_extra2 NUMBER;
v_sumatoria_ptje number;
CURSOR cur_postul IS
SELECT A.NUMRUN, ROUND(MONTHS_BETWEEN(pa_date, FECHA_NACIMIENTO) / 12) AS "AGE", 
TO_CHAR(A.NUMRUN, '09G999G999')  || '-' || DVRUN AS "RUN_POSTULANTE", UPPER(PNOMBRE) || ' ' || UPPER(SNOMBRE)
|| ' ' || UPPER(APATERNO) || ' ' || UPPER(AMATERNO) AS "NOMBRE_POSTULANTE", RANKING
FROM ANTECEDENTES_PERSONALES A JOIN POSTULACION_PROGRAMA_ESPEC P ON (A.NUMRUN = P.NUMRUN) 
JOIN PROGRAMA_ESPECIALIZACION PR ON (P.COD_PROGRAMA = PR.COD_PROGRAMA) 
JOIN INSTITUCION I ON (PR.COD_INST =  I.COD_INST) ORDER BY A.NUMRUN;
BEGIN
EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_PUNTAJE_POSTULACION';
EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_PROCESO';
EXECUTE IMMEDIATE 'TRUNCATE TABLE RESULTADO_POSTULACION';
FOR reg_postul IN cur_postul LOOP
pkg_postulacion.v_numrun := reg_postul.NUMRUN;
SELECT MAX(ROUND(MONTHS_BETWEEN(pa_date, FECHA_CONTRATO) / 12)),
ROUND(SUM(HORAS_SEMANALES)), NVL(ZONA_EXTREMA, 0) INTO v_year_contract, v_hour_work , v_zonaExtrema
FROM ANTECEDENTES_LABORALES A JOIN SERVICIO_SALUD S ON (A.COD_SERV_SALUD = S.COD_SERV_SALUD)
WHERE NUMRUN = pkg_postulacion.v_numrun GROUP BY NVL(ZONA_EXTREMA, 0);
IF v_zonaExtrema >= 1 THEN
v_ptje_zonaExtrema:= pkg_postulacion.fn_obt_ptje_zona_extrema(v_zonaExtrema);
ELSIF v_zonaExtrema = 0 THEN 
v_ptje_zonaExtrema := 0;
END IF;
v_ptje_xp :=  fn_obt_ptje_annos_experiencia(v_year_contract);
v_ptje_hour := fn_obt_ptje_horas_trab(v_hour_work);
v_ptje_rank_ins := pkg_postulacion.fn_obt_ptje_rank_insti(reg_postul.ranking);
v_sumatoria_ptje := ROUND(v_ptje_xp + v_ptje_hour + v_ptje_zonaExtrema + v_ptje_rank_ins);
IF reg_postul.age <= 44 AND v_hour_work >= 31 THEN
v_ptje_extra1 := ROUND(v_sumatoria_ptje * (pa_extra1 / 100));
ELSE
v_ptje_extra1 := 0;
END IF;
IF v_year_contract > 25 THEN
v_ptje_extra2 :=  ROUND(v_sumatoria_ptje * (pa_extra2 / 100));
ELSE
v_ptje_extra2 := 0;
END IF;
INSERT INTO DETALLE_PUNTAJE_POSTULACION VALUES(reg_postul.run_postulante, 
reg_postul.nombre_postulante, v_ptje_xp, v_ptje_hour, v_ptje_zonaExtrema,
v_ptje_rank_ins, v_ptje_extra1, v_ptje_extra2);
END LOOP;
END ;

/
CREATE OR REPLACE TRIGGER tg_postulacion
AFTER INSERT ON DETALLE_PUNTAJE_POSTULACION
FOR EACH ROW
DECLARE
v_result VARCHAR2(15);
v_sumatoria_ptje number;
BEGIN
v_sumatoria_ptje := ROUND(:NEW.PTJE_ANNOS_EXP + :NEW.PTJE_HORAS_TRAB + 
:NEW.PTJE_ZONA_EXTREMA + :NEW.PTJE_RANKING_INST + :NEW.PTJE_EXTRA_1 + :NEW.PTJE_EXTRA_2);
IF v_sumatoria_ptje >= 4500 THEN
v_result := 'SELECCIONADO';
ELSIF v_sumatoria_ptje < 4500 THEN
v_result := 'NO SELECCIONADO';
END IF;
INSERT INTO RESULTADO_POSTULACION VALUES (:NEW.RUN_POSTULANTE, v_sumatoria_ptje, v_result);
END;
/



EXEC procedure_process_post('30/06/2024', 30, 15);

--Consulta de los Postulantes procesados de la tabla DETALLE_PUNTAJE_POSTULACION--
SELECT * FROM DETALLE_PUNTAJE_POSTULACION;

--Consulta de los errores del proceso de la tabla ERROR_PROCESO--
SELECT * FROM ERROR_PROCESO;

--Consulta de los resultados de las postulacion de la tabla RESULTADO_POSTULACION--
SELECT * FROM RESULTADO_POSTULACION;
