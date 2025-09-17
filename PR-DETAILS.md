# Smart Property Insurance: Contracts and Development Branch

This pull request introduces the initial smart contracts and project scaffolding for Smart Property Insurance.

## Summary

- Added two Clarity contracts:
  - iot-sensor-oracle: Manages registration, status, and data updates from property IoT sensors with validation support.
  - risk-based-premium-adjustment: Provides policy lifecycle, risk assessment-based premium adjustment, and automated claims processing.
- Updated Clarinet project configuration, added initial test files.
- Ensured contracts compile successfully with clarinet check.

## Motivation

Enable transparent, data-driven property insurance that adjusts premiums based on live risk indicators from sensors while facilitating faster, verifiable claims processing.

## What’s Included

- contracts/iot-sensor-oracle.clar
- contracts/risk-based-premium-adjustment.clar
- tests/iot-sensor-oracle.test.ts
- tests/risk-based-premium-adjustment.test.ts
- Clarinet.toml adjustments

## Implementation Details

- Sensor oracle contract:
  - Register sensors with type and metadata
  - Update and validate sensor data with role-based authorization
  - Track property sensor counts and statuses
- Premium adjustment contract:
  - Create policies with base premiums, coverage, and duration
  - Perform weighted risk assessments to derive new premiums
  - Submit and process claims with payout controls and fund tracking

## How to Verify

1. Run clarinet check to confirm the contracts are valid.
2. Review the data maps and functions for access control and state updates.

Commands:
- clarinet check

## Risks and Trade-offs

- No external or cross-contract calls: contracts are self-contained by design per requirement.
- Warnings about unchecked inputs are expected and acceptable for this prototype.

## Follow-ups

- Expand tests to cover edge cases and negative paths
- Add policy payments and premium collection workflows
- Enhance risk scoring sensitivity and parameterization

## Screenshots/Logs

- N/A
