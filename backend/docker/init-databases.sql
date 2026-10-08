SELECT 'CREATE DATABASE xiuxian_test'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'xiuxian_test')\gexec
