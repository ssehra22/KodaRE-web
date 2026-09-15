-- KodaRE — Phase 6 schema: Vendor Directory drill-down additions (Scope §4.9).
-- Run this once in your Supabase project's SQL Editor (Project → SQL Editor → New query).
-- Safe to re-run: uses "add column if not exists" throughout.
-- Additive only — adds columns to the existing `vendors` table for fields that didn't
-- have a home yet: Service Type (Default), Comments, User Notes, and Specific Properties
-- (a free-text field, e.g. "Fox-1, Highlands" or "All").
-- No RLS changes needed — existing vendors policies already cover these columns.

alter table vendors add column if not exists service_type text;
alter table vendors add column if not exists comments text;
alter table vendors add column if not exists user_notes text;
alter table vendors add column if not exists properties text;

-- If you already ran an earlier version of this file that added `properties` as jsonb
-- (or a `contract` column), both are harmless to leave in place — a plain string still
-- stores fine in a jsonb column, and an unused `contract` column just sits there unread.
