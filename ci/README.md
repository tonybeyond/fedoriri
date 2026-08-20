# CI GitHub Actions

`github-workflow-ci.yml` doit vivre dans `.github/workflows/ci.yml`, mais le
token fourni pour le push initial n'a pas le scope `workflow` (GitHub refuse
la création de workflows sans lui). Pour activer la CI :

```bash
mkdir -p .github/workflows
git mv ci/github-workflow-ci.yml .github/workflows/ci.yml
git commit -m "Active la CI"
git push   # avec un token disposant du scope workflow, ou en SSH
```
