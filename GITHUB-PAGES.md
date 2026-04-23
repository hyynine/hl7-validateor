# GitHub Pages 公网部署

这个仓库已经包含 GitHub Pages 工作流：

- [`.github/workflows/deploy-pages.yml`](./.github/workflows/deploy-pages.yml)

## 最短步骤

1. 在 GitHub 新建一个仓库。
2. 把当前目录推送到该仓库的 `main` 分支。
3. 打开 GitHub 仓库页面。
4. 进入 `Settings` -> `Pages`。
5. 在 `Build and deployment` 的 `Source` 里选择 `GitHub Actions`。
6. 等待 `Actions` 里的 `Deploy GitHub Pages` 工作流跑完。

## 访问地址

- 如果仓库名是普通项目名，例如 `hl7-validator`：
  `https://<你的 GitHub 用户名>.github.io/hl7-validator/`
- 如果仓库名本身就是 `<你的 GitHub 用户名>.github.io`：
  `https://<你的 GitHub 用户名>.github.io/`

## 命令示例

把下面的占位符替换成你自己的 GitHub 用户名和仓库名：

```powershell
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<username>/<repo>.git
git push -u origin main
```

## 说明

- 当前页面是纯静态前端，适合直接部署到 GitHub Pages。
- 工作流只发布 `index.html`，不会把本地启动脚本和说明文档暴露到公网。
- 如果你后面绑定自定义域名，可以在仓库根目录新增 `CNAME` 文件，工作流会一起发布。
