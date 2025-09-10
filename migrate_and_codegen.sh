#!/bin/bash

# ==============================
# Script: migrate_and_codegen.sh
# Description: Run all Flyway migrations and Jooq codegen
# ==============================

set -e  # nếu lệnh nào fail thì dừng luôn

echo ">>> Starting Flyway migrations..."

./gradlew :flyway:antisocialcheck:flywayMigrate
./gradlew :flyway:claim:flywayMigrate
./gradlew :flyway:consumer:flywayMigrate
./gradlew :flyway:dataio:flywayMigrate
./gradlew :flyway:management:flywayMigrate
./gradlew :flyway:parametrictrigger:flywayMigrate
./gradlew :flyway:payment:flywayMigrate
./gradlew :flyway:policy:flywayMigrate
./gradlew :flyway:products:flywayMigrate

echo ">>> Running global Flyway tasks..."
./gradlew flywayMigrate flywayInfo

echo ">>> Running Jooq codegen..."
./gradlew jooqCodegen

echo ">>> All tasks completed successfully."
