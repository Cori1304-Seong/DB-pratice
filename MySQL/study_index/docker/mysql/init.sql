-- 초기 DB/계정 생성 및 권한 부여 (환경변수로도 생성되지만 예시용)
CREATE DATABASE IF NOT EXISTS study_index CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'study_index_user'@'%' IDENTIFIED BY 'study_index_pass';
GRANT ALL PRIVILEGES ON study_index.* TO 'study_index_user'@'%';
FLUSH PRIVILEGES;
