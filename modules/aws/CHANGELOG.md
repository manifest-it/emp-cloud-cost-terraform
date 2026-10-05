# Changelog

## [2.2.0](https://github.com/manifest-it/emp-cloud-cost-terraform/compare/aws-terraform-v2.1.0...aws-terraform-v2.2.0) (2026-10-05)


### Features

* **aws:** allow collector to resolve account display names ([4ca6644](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/4ca66441717d285a863d376fe0f8810bcd6991c4))
* **aws:** allow collector to resolve account display names ([16523a9](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/16523a9e85570abc61297383d7caf3e2408813c7))

## [2.1.0](https://github.com/manifest-it/emp-cloud-cost-terraform/compare/aws-terraform-v2.0.1...aws-terraform-v2.1.0) (2026-10-05)


### Features

* **aws:** pass Cost Source Configuration ID to collector ([560d74a](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/560d74a91b482c293c76eb39c51b0b59b8790a58))
* **aws:** pass Cost Source Configuration ID to collector ([0396b8b](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/0396b8b2bdb5b8b65cb8310f27f4d012bfe1526b))

## [2.0.1](https://github.com/manifest-it/emp-cloud-cost-terraform/compare/aws-terraform-v2.0.0...aws-terraform-v2.0.1) (2026-10-05)


### Bug Fixes

* **aws:** use unversioned cost endpoint ([e551a12](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/e551a12d16502d1f3b6433b16e572989ccaf8a8e))

## [2.0.0](https://github.com/manifest-it/emp-cloud-cost-terraform/compare/aws-terraform-v1.1.0...aws-terraform-v2.0.0) (2026-10-01)


### ⚠ BREAKING CHANGES

* **aws:** replace x_api_key with mit_api_key and require the /api/v1/client/cost ingestion endpoint.

### Features

* **aws:** support MIT API key ingestion ([7c026cf](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/7c026cfd9f97d20f1b38b475ae91d820ab809d99))

## [1.1.0](https://github.com/manifest-it/emp-cloud-cost-terraform/compare/aws-terraform-v1.0.0...aws-terraform-v1.1.0) (2026-09-23)


### Features

* **aws:** expose rolling 15-day backfill ([8cdce03](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/8cdce037e5b0be169ad5196e240d7439d1d2d1b1))

## [1.0.0](https://github.com/manifest-it/emp-cloud-cost-terraform/compare/aws-terraform-v0.2.0...aws-terraform-v1.0.0) (2026-09-22)


### ⚠ BREAKING CHANGES

* **aws:** the AWS module no longer accepts name_prefix; connector resource names are fixed to emp-aws-cloud-cost-agent.

### Features

* **aws:** fix Empirik connector naming ([3b5133d](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/3b5133de36161b184ab866d605eab7e010fb19c6))

## [0.2.0](https://github.com/manifest-it/emp-cloud-cost-terraform/compare/aws-terraform-v0.1.0...aws-terraform-v0.2.0) (2026-09-22)


### Features

* **aws:** support existing VPC attachment ([fced728](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/fced728267832d6eada428c45ff3f30b82bc79f1))

## 0.1.0 (2026-09-22)


### Features

* add AWS cloud cost Terraform module ([60fbc70](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/60fbc7025bfbae2ac3a0f54fad1ea47197617dd1))
* **aws:** accept UI-provided EMP credentials ([3fddee4](https://github.com/manifest-it/emp-cloud-cost-terraform/commit/3fddee4098c733e156c49474d92cf65cea5da3d3))
