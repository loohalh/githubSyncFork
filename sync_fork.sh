#!/bin/bash

# v1.0.0
# by looha
# fork 其他项目，并同步所有分支以及 release
# 可添加定时任务执行脚本同步源仓库所有变更
# 执行脚本前请确保在githua上已fork源仓库，并正确配置github ssh 访问，以及 API TOKEN
# 依赖git、jq,请自行安装


SOURCE_OWNER=""   # 源仓库用户
SOURCE_REPO=""    # 源仓库名称
FORK_OWNER=""     # fork仓库用户
FORK_REPO=""      # fork仓库名称
GITHUB_TOKEN=""   # gitHub Token

COMPLETED_LOG="./completed_releases.log"


function show_help() {
  echo "Usage: $0 -s <SOURCE_OWNER> -r <SOURCE_REPO> -f <FORK_OWNER> -k <GITHUB_TOKEN> -t <FORK_REPO>"
  echo
  echo "Options:"
  echo "  -s <SOURCE_OWNER>  GitHub username or organization of the source repository"
  echo "  -r <SOURCE_REPO>   Name of the source repository"
  echo "  -f <FORK_OWNER>    GitHub username or organization of the fork repository"
  echo "  -t <FORK_REPO>     Name of the fork repository"
  echo "  -k <GITHUB_TOKEN>  Personal Access Token (PAT) for GitHub API authentication"
  echo "  -h, --help         Show this help message and exit"
  echo
  echo "Example:"
  echo "  $0 -s usernam_source -r repo_name -f username_yourname -t repo_name -k ghp_xxxxxxxxxxxx"
}

# 解析参数
while getopts "s:r:f:t:k:h" opt; do
  case $opt in
    s) SOURCE_OWNER="$OPTARG" ;;   # 源仓库用户
    r) SOURCE_REPO="$OPTARG" ;;    # 源仓库名称
    f) FORK_OWNER="$OPTARG" ;;     # fork仓库用户
    t) FORK_REPO="$OPTARG" ;;      # fork仓库名称
    k) GITHUB_TOKEN="$OPTARG" ;;   # gitHub Token
    h) show_help; exit 0 ;;        # 显示帮助
    *)
      echo "Invalid option: -$OPTARG" >&2
      show_help
      exit 1
      ;;
  esac
done

# 必要参数
if [[ -z "$SOURCE_OWNER" || -z "$SOURCE_REPO" || -z "$FORK_OWNER" || -z "$FORK_REPO" || -z "$GITHUB_TOKEN" ]]; then
  echo "Error: Missing required arguments."
  show_help
  exit 1
fi

echo -e "\n\n\n\n"
start_time=$(date +"%Y-%m-%d %H:%M:%S.%3N")
echo -e "-----------------开始：start_time:$start_time -------------------"


#进入工作目录
to_dir() {
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    cd "$SCRIPT_DIR" || exit
    echo "Current script execution path ：$SCRIPT_DIR"
}

# clone并进入 Fork 仓库目录
clone_repo() {
    if [[ -d "$FORK_REPO" ]]; then
        # 如果目录存在，直接进入
        echo "✅ Directory '$FORK_REPO' exists. Entering directory..."
        cd "$FORK_REPO"
    else
        # 目录不存在，clone Fork 仓库
        echo "📥 Cloning fork repository: git@github.com:$FORK_OWNER/$FORK_REPO.git"
        git clone --depth=1 --no-checkout "git@github.com:$FORK_OWNER/$FORK_REPO.git"
        cd "$FORK_REPO"
        
        # 添加上游仓库
        echo "🔗 Adding upstream repository: git@github.com:$SOURCE_OWNER/$SOURCE_REPO.git"
        git remote add upstream "git@github.com:$SOURCE_OWNER/$SOURCE_REPO.git"
        echo "✅ Remote 'upstream' added: git@github.com:$SOURCE_OWNER/$SOURCE_REPO.git"
    fi
}


# 同步分支
fetch_update_branch() {
    # 同步上游仓库
    git fetch --depth=1 upstream
    
    branches=$(git branch -r | grep -v '\->' | awk -F/ '{print $2}')
    
    for branch in $branches; do
        echo "🌿 Fetching branch: $branch"
        git branch temp
        git checkout temp
        git branch -D $branch
        git fetch upstream $branch:$branch --depth=1
#        git reset --hard upstream/$branch
#        git branch $branch
        git checkout $branch
        echo "🚀 Pushing branch: $branch to fork..."
        git push --force origin $branch
        git branch -D temp
    done
    
    echo "🎉 All branches have been cloned and pushed to the fork repository!"
}

# 同步上游 tags
fetch_tags() {
    git fetch upstream --tags --depth=1
    tags=$(git tag -l)
    echo "🔄 Found the following tags: $tags"
}

# 更新 tags
update_tags() {
    total_tags=$(echo "$tags" | wc -l)
    batch_size=10
    batch_start=1
    
    echo "总共有 $total_tags 个 tags，需要分批推送。每批推送 $batch_size 个。"
    
    while [ $batch_start -le $total_tags ]; do
        batch_end=$((batch_start + batch_size - 1))
        echo "推送第 $batch_start 到第 $batch_end 个 tags..."
        
        batch_tags=$(echo "$tags" | sed -n "${batch_start},${batch_end}p")
        echo "开始推送：$batch_tags"
        
        git push origin $batch_tags
        if [ $? -ne 0 ]; then
            echo "分支： $batch_tags 推送失败，请检查网络或远程仓库设置。"
        fi
        
        batch_start=$((batch_end + 1))
    done
    
    echo "所有 tags 推送完成！"
}

# 获取并更新 release，下载上传release附件
fetch_update_release_assets() {
    local tag_name="$1"
    echo "🔄 Processing release for tag: $tag_name..."

    # 获取源仓库的release信息
    release_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$SOURCE_OWNER/$SOURCE_REPO/releases/tags/$tag_name")

    if [[ "$(echo "$release_info" | jq -r '.message')" == "Not Found" ]]; then
        echo "⚠️ No release found for tag: $tag_name. Skipping..."
        return
    fi

    # 提取release信息
    release_name=$(echo "$release_info" | jq -r '.name // "Release for tag $tag_name"')
    release_body=$(echo "$release_info" | jq -r '.body // ""' | jq -sRr .)
    asset_urls=$(echo "$release_info" | jq -r '.assets[]?.browser_download_url')

    if [[ -z "$asset_urls" ]]; then
        echo "❌ No assets found for release: $tag_name. Skipping..."
        return
    fi

    # 下载所有release文件
    local download_dir="./downloads/$tag_name"
    mkdir -p "$download_dir"
    for asset_url in $asset_urls; do
        file_name=$(basename "$asset_url")
        local_file="$download_dir/$file_name"

        # 检查是否已下载上传过
        if grep -q "$file_name" "$COMPLETED_LOG"; then
            echo "✅ File already processed: $file_name. Skipping download and upload..."
            continue
        fi

        # 下载文件
        echo "🔄 Downloading asset: $file_name from $asset_url"
        curl -L -H "Authorization: token $GITHUB_TOKEN" "$asset_url" -o "$local_file"

        if [[ -f "$local_file" ]]; then
            echo "✅ Successfully downloaded: $file_name"
        else
            echo "❌ Failed to download: $file_name"
            return
        fi
    done

    echo "✅ All assets for release $tag_name downloaded to $download_dir."

    # 检查fork仓库是否已存在对应release
    fork_release=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$FORK_OWNER/$FORK_REPO/releases/tags/$tag_name")

    upload_url=$(echo "$fork_release" | jq -r '.upload_url' | sed 's/{?name,label}//')

    if [[ "$upload_url" == "null" || -z "$upload_url" ]]; then
        json_payload=$(jq -n \
            --arg tag_name "$tag_name" \
            --arg name "$release_name" \
            --arg body "$release_body" \
            '{tag_name: $tag_name, name: $name, body: $body}')

        echo "📤 Creating release with payload: $json_payload"

        fork_release=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$json_payload" \
            "https://api.github.com/repos/$FORK_OWNER/$FORK_REPO/releases")

        upload_url=$(echo "$fork_release" | jq -r '.upload_url' | sed 's/{?name,label}//')

        if [[ -z "$upload_url" || "$upload_url" == "null" ]]; then
            echo "❌ Error: Failed to create or retrieve release in fork repository."
            echo "Response: $fork_release"
            return
        fi
        echo "✅ Fork release created. Upload URL: $upload_url"
    else
        echo "🔄 Release already exists in fork repository. Using existing release."
    fi

    # 获取已上传的文件列表
    uploaded_assets=$(echo "$fork_release" | jq -r '.assets[].name')

    # 上传文件到fork仓库
    for asset_file in "$download_dir"/*; do
        file_name=$(basename "$asset_file")

        # 跳过已上传的文件
        if echo "$uploaded_assets" | grep -q "$file_name"; then
            echo "✅ Asset already uploaded: $file_name. Skipping upload..."
            echo "$file_name" >> "$COMPLETED_LOG"
            continue
        fi

        echo "🔄 Uploading $file_name to fork release..."
        curl -X POST -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @"$asset_file" \
            "$upload_url?name=$file_name"

        if [[ $? -eq 0 ]]; then
            echo "✅ Uploaded $file_name."
            echo "$file_name" >> "$COMPLETED_LOG"
        else
            echo "❌ Failed to upload $file_name."
        fi
    done

    #删除下载文件夹
    echo "🧹 Cleaning up downloaded assets for tag $tag_name..."
    rm -rf "$download_dir"
    echo "✅ Tag $tag_name has cleanup completed"
}

# 循环处理 release
fetch_update_release_workflow() {
    if [[ ! -f $COMPLETED_LOG ]]; then
	   touch "$COMPLETED_LOG"
    fi
    
    for tag in $tags; do
        fetch_update_release_assets "$tag"
    done
    echo "✅ All releases have been successfully synced to your fork repository!"
}

#执行
to_dir
clone_repo
fetch_update_branch
fetch_tags
update_tags
fetch_update_release_workflow

end_time=$(date +"%Y-%m-%d %H:%M:%S.%3N")
echo -e "-----------------结束：end_time: $end_time -------------------"



