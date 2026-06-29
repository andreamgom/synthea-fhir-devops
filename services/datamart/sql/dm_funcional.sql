-- dm_funcional.sql
-- Datamart de evolución funcional: escalas basal vs alta por paciente

CREATE TABLE IF NOT EXISTS dm_funcional AS
SELECT
    p.id                                    AS patient_id,
    p.name_family                           AS apellido,
    p.name_given                            AS nombre,
    p.birth_date                            AS fecha_nacimiento,
    p.gender                                AS sexo,
    obs_basal.code_display                  AS escala,
    obs_basal.code_code                     AS loinc_code,
    obs_basal.value_quantity_value          AS valor_basal,
    obs_alta.value_quantity_value           AS valor_alta,
    obs_alta.value_quantity_value 
        - obs_basal.value_quantity_value    AS delta,
    enc.period_start                        AS fecha_ingreso,
    enc.period_end                          AS fecha_alta
FROM hfj_resource p
JOIN hfj_res_ver pv ON p.res_id = pv.res_id
    AND pv.res_type = 'Patient'
JOIN hfj_resource enc_r ON enc_r.res_type = 'Encounter'
JOIN hfj_res_ver enc ON enc_r.res_id = enc.res_id
JOIN hfj_resource obs_basal_r ON obs_basal_r.res_type = 'Observation'
JOIN hfj_res_ver obs_basal ON obs_basal_r.res_id = obs_basal.res_id
JOIN hfj_resource obs_alta_r ON obs_alta_r.res_type = 'Observation'
JOIN hfj_res_ver obs_alta ON obs_alta_r.res_id = obs_alta.res_id
LIMIT 0; -- placeholder: HAPI FHIR usa esquema interno optimizado