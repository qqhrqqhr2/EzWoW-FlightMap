# GitHub releases -> CurseForge

## One-time setup

1. Generate an upload token in CurseForge Authors -> Settings -> API Tokens.
2. In this GitHub repository, open Settings -> Secrets and variables -> Actions.
3. Add a repository secret named `CF_API_TOKEN` with that token as its value.
   Never paste the token into source code, release notes or issue comments.

## Publish

1. Update `## Version` in the addon TOC and `RELEASE_NOTES.md` (heading `# v<version>`) with user-facing English/Korean changes, then commit all addon changes.
2. Create a GitHub release for that commit with tag `v<TOC version>` (for example `v1.0.0`).
3. Click **Publish release**. The `Release to CurseForge` workflow validates the package,
   creates the installable ZIP and uploads to the project ID in `release.json`.
   A GitHub prerelease becomes a CurseForge beta; a normal release becomes a release.
4. Check Actions for the result. The ZIP, checksum, metadata and successful upload
   receipt (CurseForge file ID) are retained as workflow artifacts for 30 days.

Draft releases and plain tag pushes do not upload. Use a new matching version/tag
for each release. Workflows must be present in the tagged commit.
CurseForge moderation can delay public availability, particularly for new projects.
Do not blindly re-run an upload after a timeout: it may already have been accepted.
Check the project file list first to avoid publishing duplicate files.

## Manual runs and local builds

Actions -> Release to CurseForge -> Run workflow builds only by default.
Enable `upload` to upload the selected branch's TOC version.
Requires Python 3.10 or later locally:

```sh
python -m unittest discover -s scripts -p test_release.py
python scripts/release.py
```

This checks TOC/XML file references and project/interface metadata and creates a
deterministic ZIP, checksum and upload metadata in `dist/`. There is one addon
folder at the ZIP root. Documentation, scripts and repository configuration are
excluded. To upload locally, set `CF_API_TOKEN` in the environment, then run:

```sh
python scripts/release.py --upload
```

Game target: WoW Forever 1.60.1, Interface 16001.
API reference: https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api

## 한국어

- 최초 한 번: CurseForge 업로드 토큰을 저장소 Actions Secret `CF_API_TOKEN`으로 등록합니다.
- TOC 버전을 올리고 커밋한 뒤 같은 버전의 태그(예: `v1.0.0`)로 GitHub 릴리즈를 게시하면 자동 업로드합니다.
- 임시 저장, 단순 태그 푸시는 배포하지 않습니다. GitHub 사전 릴리즈는 CurseForge Beta로 등록합니다.
- ZIP 생성만 시험하려면 Actions에서 수동 실행하고 upload를 끈 상태로 둡니다.
- 성공 시 파일 ID가 포함된 업로드 영수증을 Actions 아티팩트에서 확인할 수 있습니다.
- 새 프로젝트는 CurseForge 검토·승인 후 공개될 수 있습니다.

CurseForge changelogs always come from `RELEASE_NOTES.md`, not the GitHub release body. The notes version must match the TOC version.

CurseForge 변경 내역은 GitHub 본문 대신 저장소 `RELEASE_NOTES.md`를 사용합니다. 문서 버전과 TOC 버전이 다르면 배포를 중단합니다.
