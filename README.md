# githubSyncFork
自动同步 github fork 项目的 branch、tag、release
###可添加定时任务执行脚本同步源仓库所有变更

## 依赖
依赖git、jq,请自行安装

## 使用指南
1、执行脚本前请确保在githua上已fork源仓库，并自行正确配置github ssh 访问，以及 Api token

2、下载脚本到准备clone项目的跟目录，后续都在该目录操作

```
cd myRepos
curl -O https://raw.githubusercontent.com/loohalh/githubSyncFork/refs/heads/main/sync_fork.sh && chmod +x sync_fork.sh
```
3、使用
```
bash sync_fork.sh -s usernam_source -r repo_name -f username_yourname -t repo_name -k ghp_xxxxxxxxxxxx

### help
bash sync_fork.sh -s

### 参数说明
-s <SOURCE_OWNER>  源仓库用户
-r <SOURCE_REPO>   源仓库名称
-f <FORK_OWNER>    fork仓库用户名
-t <FORK_REPO>     fork仓库名称
-k <GITHUB_TOKEN>  Git hub  Access Token (PAT) for GitHub API 
-h --help          帮助菜单
```




