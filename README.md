# XL Deploy GitHub Action

## Overview
This GitHub Action allows users to publish, install, or uninstall deployment packages on XL Deploy. It provides an automated way to interact with XL Deploy by executing necessary API calls to manage application deployments.

## Features
- Publish, install, and uninstall deployment packages
- Monitor deployment logs
- Securely authenticate with XL Deploy
- Support for rollback functionality

## Inputs
| Input Name          | Description                  | Required | Type    |
|--------------------|------------------------------|----------|--------|
| `goal`             | Deployment goal               | ✅        | string |
| `rollback`         | Rollback (true/false)        | ✅        | boolean|
| `xldurl`          | XL Deploy URL                | ✅        | string |
| `xldusername`     | XL Deploy Username           | ✅        | string |
| `xldpassword`     | XL Deploy Password           | ✅        | string |
| `darpackage`      | DAR Package                  | ✅        | string |
| `targetenvironment` | Target Environment          | ✅        | string |

## Usage
Add the following example to your GitHub Actions workflow:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v3
      
      - name: Deploy to XL Deploy
        uses: your-repo/xl-deploy-action@v1
        with:
          goal: "deploy"
          rollback: "false"
          xldurl: "https://your-xld-instance.com"
          xldusername: "admin"
          xldpassword: "your-password"
          darpackage: "your-package.dar"
          targetenvironment: "your-environment"
```
## How It Works
1. The action executes a PowerShell script (`xldgha.ps1`).
2. It connects to XL Deploy using the provided credentials.
3. Depending on the `goal` input, it will:
   - Upload a DAR package
   - Deploy the package to the target environment
   - Uninstall the deployment if needed
4. It continuously monitors and fetches deployment logs.

## Security Considerations
- Use GitHub Secrets to store sensitive information like `xldpassword`.
- Ensure proper access control on your XL Deploy instance.
