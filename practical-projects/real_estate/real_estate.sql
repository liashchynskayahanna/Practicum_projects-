/* Проект: Анализ данных для агентства недвижимости. ad hoc задачи
*/

-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Определим аномальные значения (выбросы) по значению перцентилей
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),

-- Найдём id объявлений, которые не содержат выбросы
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
            OR ceiling_height IS NULL)
),

-- Классифицируем  по региону и времени активности
category AS (
    SELECT 
        a.id,
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region,
        
        -- Объявления по времени активности (в днях)
        CASE 
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'до месяца'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до трёх месяцев'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
            WHEN a.days_exposition >= 181 THEN 'больше полугода'
            ELSE 'не указано'
        END AS activity_period,
        
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        f.ceiling_height,
        f.kitchen_area,
        f.floors_total,
        f.open_plan,
        f.is_apartment,
        (a.last_price / f.total_area) AS price_m2                 -- Считаем цену за квадратный метр
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f ON a.id = f.id
    JOIN real_estate.city AS c ON f.city_id = c.city_id
    JOIN real_estate.type AS t ON f.type_id = t.type_id
    WHERE 
        f.id IN (SELECT * FROM filtered_id)                           -- Только квартиры без выбросов
        AND t.type = 'город'                                          -- Только тип "город"
        AND a.days_exposition IS NOT NULL                             -- Только объявления с известным сроком активности
)

SELECT 
    region,                          -- Регион: Санкт-Петербург или ЛенОбл
    activity_period,                 -- Категория по времени активности
    COUNT(*) AS total_ads,           -- Сколько объявлений в группе
    ROUND(AVG(days_exposition)::NUMERIC, 0) AS avg_days_exposition,   -- Среднее количество дней активности объявления
    ROUND(AVG(price_m2)::NUMERIC, 2) AS avg_price_m2,         -- Средняя цена за м²
    ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area,             -- Средняя площадь квартиры
    ROUND(AVG(kitchen_area)::NUMERIC, 2) AS avg_kitchen_area,         -- Средняя площадь кухни
    ROUND(AVG(rooms)::NUMERIC, 2) AS avg_rooms,                       -- Среднее количество комнат
    ROUND(AVG(balcony)::NUMERIC, 2) AS avg_balconies,                 -- Среднее количество балконов
    ROUND(AVG(ceiling_height)::NUMERIC, 2) AS avg_ceiling_height,     -- Средняя высота потолков
    ROUND(AVG(floors_total)::NUMERIC, 2) AS avg_floors_total,         -- Средняя этажность дома
    ROUND(SUM(COALESCE(open_plan, 0))::NUMERIC / COUNT(*), 4) AS share_open_plan,    -- Доля квартир с открытой планировкой
    ROUND(SUM(COALESCE(is_apartment, 0))::NUMERIC / COUNT(*), 4) AS share_apartments -- Доля апартаментов
FROM category
GROUP BY region, activity_period
ORDER BY region DESC, activity_period;


-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

WITH limits AS (
    SELECT 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.total_area) AS total_area_limit,         
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.rooms) AS rooms_limit,                   
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.balcony) AS balcony_limit,               
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY f.ceiling_height) AS ceiling_height_limit_99, 
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY f.ceiling_height) AS ceiling_height_limit_1   
    FROM real_estate.flats AS f
),

filtered_id AS (
    SELECT f.id AS id
    FROM real_estate.flats AS f
    WHERE f.total_area < (SELECT total_area_limit FROM limits)
      AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
      AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
      AND (
            (f.ceiling_height <= (SELECT ceiling_height_limit_99 FROM limits)
             AND f.ceiling_height >= (SELECT ceiling_height_limit_1 FROM limits))
             OR f.ceiling_height IS NULL)
),

months_ads AS (
    SELECT 
        a.id,
        a.first_day_exposition,                                                              -- Дата публикации объявления
        a.days_exposition,                                                                   -- Длительность публикации
        a.last_price,                                                                        -- Последняя указанная цена
        f.total_area,                                                                        -- Площадь квартиры
        EXTRACT(MONTH FROM a.first_day_exposition) AS month_first_ads,                       -- Месяц публикации
        EXTRACT(MONTH FROM (a.first_day_exposition + a.days_exposition * INTERVAL '1 day')) AS month_last_ads, -- Месяц снятия
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'                           -- Классификация по региону
            ELSE 'ЛенОбл'
        END AS region
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f ON a.id = f.id
    JOIN real_estate.city AS c ON f.city_id = c.city_id
    WHERE a.id IN (SELECT id FROM filtered_id)
),
 -- Статистика по месяцу публикации объявлений
first_exposition AS (
    SELECT 
        region,
        month_first_ads AS month_ads,
        COUNT(*) AS count_first_ads,                                                         -- Кол-во объявлений в месяц публикации
        ROUND(AVG(a.last_price / f.total_area)::NUMERIC, 2) AS first_avg_cost_per_sq_m,      -- Средняя цена за м²
        ROUND(AVG(f.total_area)::NUMERIC, 2) AS first_avg_total_area,                        -- Средняя площадь
        ROUND(COUNT(*)::NUMERIC / (SELECT COUNT(*) FROM months_ads), 4) AS share_ads         -- Доля всех публикаций в месяце
    FROM months_ads AS a
    JOIN real_estate.flats AS f ON a.id = f.id
    WHERE EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018                    -- Ограничение по годам
    GROUP BY region, month_first_ads
),
--Статистика по месяцу снятия объявлений с публикации
last_exposition AS (
    SELECT 
        region,
        month_last_ads AS month_ads,
        COUNT(*) AS count_last_ads,                                                          -- Кол-во снятых объявлений
        ROUND(AVG(a.last_price / f.total_area)::NUMERIC, 2) AS last_avg_cost_per_sq_m,       -- Средняя цена за м²
        ROUND(AVG(f.total_area)::NUMERIC, 2) AS last_avg_total_area,                         -- Средняя площадь
        ROUND(COUNT(*)::NUMERIC / (SELECT COUNT(*) FROM months_ads), 4) AS share_off_market  -- Доля снятий в месяце
    FROM months_ads AS a
    JOIN real_estate.flats AS f ON a.id = f.id
    WHERE a.days_exposition IS NOT NULL
    GROUP BY region, month_last_ads
)

SELECT 
    COALESCE(fe.region, le.region) AS region,                                     
    CASE COALESCE(fe.month_ads, le.month_ads)                                     
        WHEN 1 THEN 'январь'
        WHEN 2 THEN 'февраль'
        WHEN 3 THEN 'март'
        WHEN 4 THEN 'апрель'
        WHEN 5 THEN 'май'
        WHEN 6 THEN 'июнь'
        WHEN 7 THEN 'июль'
        WHEN 8 THEN 'август'
        WHEN 9 THEN 'сентябрь'
        WHEN 10 THEN 'октябрь'
        WHEN 11 THEN 'ноябрь'
        WHEN 12 THEN 'декабрь'
    END AS month_ads_name,

    -- Ранжирование месяца по количеству публикаций (в рамках региона)
    RANK() OVER (PARTITION BY COALESCE(fe.region, le.region) ORDER BY COALESCE(fe.count_first_ads, 0) DESC) AS rank_publication,
    fe.count_first_ads,
    fe.first_avg_cost_per_sq_m,
    fe.first_avg_total_area,
    fe.share_ads,

    -- Ранжирование месяца по количеству снятий (в рамках региона)
    RANK() OVER (PARTITION BY COALESCE(fe.region, le.region) ORDER BY COALESCE(le.count_last_ads, 0) DESC) AS rank_removal,
    le.count_last_ads,
    le.last_avg_cost_per_sq_m,
    le.last_avg_total_area,
    le.share_off_market

FROM first_exposition AS fe
FULL JOIN last_exposition AS le 
    ON fe.month_ads = le.month_ads AND fe.region = le.region
ORDER BY region, fe.month_ads; 


-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.


WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,     
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,                
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,            
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,  
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l   
    FROM real_estate.flats     
),

filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL) 
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL) 
        AND (
            (ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
             AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits))
            OR ceiling_height IS NULL)
),
data_clean AS (
    SELECT 
        f.id AS id,
        c.city AS city,
        t.type AS type, 
        a.first_day_exposition AS first_day_exposition,
        a.days_exposition AS days_exposition, 
        a.last_price AS last_price,          
        f.total_area AS total_area,           
        a.last_price / f.total_area AS price_per_sqm                              -- Цена за квадратный метр
    FROM real_estate.flats AS f
    JOIN real_estate.advertisement AS a ON a.id = f.id
    JOIN real_estate.city AS c ON f.city_id = c.city_id
    JOIN real_estate.type AS t ON f.type_id = t.type_id
    WHERE f.id IN (SELECT id FROM filtered_id)                                     -- Только отфильтрованные объявления
      AND c.city != 'Санкт-Петербург'                                              -- Оставляем только Ленобласть
),

summary AS (
    SELECT
        city,
        COUNT(*) AS total_ads,                                                      -- Всего объявлений
        COUNT(*) FILTER (WHERE days_exposition IS NOT NULL) AS removed_ads,         -- Объявлений, снятых с продажи
        ROUND(AVG(price_per_sqm)::NUMERIC, 2) AS avg_price_per_sqm,                 -- Средняя цена за кв.м.
        ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area,                       -- Средняя площадь
        ROUND(AVG(days_exposition)::NUMERIC, 2) AS avg_days_exposition,             -- Среднее время объявлений
        ROUND((COUNT(*) FILTER (WHERE days_exposition IS NOT NULL)::FLOAT / COUNT(*))::NUMERIC, 4) AS removed_share -- Доля снятых с продажи объявлений
    FROM data_clean
    GROUP BY city
),
top_cities AS (
    SELECT *
    FROM summary
    WHERE total_ads >= 50
)
SELECT *                                                                            --Tоп-15 городов
FROM top_cities
ORDER BY removed_share DESC

LIMIT 15;
