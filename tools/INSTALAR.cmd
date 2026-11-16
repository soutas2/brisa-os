@echo off
rem Abre o PREPARAR-FEDORA.ps1 como administrador
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0PREPARAR-FEDORA.ps1'"
