#!/usr/bin/env bash

#============================================================
# File: uvinit.sh
# Description: 初始化 uv 项目
# URL: 
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2025-07-06
# UpdatedAt: 2025-07-06
#============================================================

if [[ -n "$DEBUG" ]]; then
    set -eux
else
    set -euo pipefail
fi

# 获取当前目录名并转换为大写和下划线格式
setup_directory_names() {
    current_dirname=$(basename "$(pwd)")
    upper_dirname=${current_dirname^^}  # 直接使用 Bash 参数扩展转换为大写
    sub_dirname=${current_dirname//-/_}  # 将连字符替换为下划线
}

# 创建 README.md 文件
create_readme() {
    if [[ ! -f README.md ]]; then
        echo "Creating new README.md file"
        echo "# ${upper_dirname}" > README.md
    else
        echo "README.md already exists, skipping creation"
    fi
}

# 配置 pyproject.toml 文件
configure_project() {
    local toml_file="pyproject.toml"
    if ! grep -q "\[project.scripts\]" "${toml_file}"; then
        {
            echo ""
            echo "[project.scripts]"
            echo "${sub_dirname} = \"${sub_dirname}.entry:main\""
        } >> "${toml_file}"
        echo "Added [project.scripts] to ${toml_file}"
    fi

    if ! grep -q "\[tool.uv\]" "${toml_file}"; then
        {
            echo ""
            echo "[tool.uv]"
            echo "package = true"
        } >> "${toml_file}"
        echo "Added [tool.uv] to ${toml_file}"
    fi
}

# 初始化项目
init_project() {
    local toml_file="pyproject.toml"
    if [[ -f ${toml_file} ]]; then
        read -r -p "pyproject.toml exists. Reset project? (y/n): " confirm
        if [[ "${confirm,,}" == "y" ]]; then
            echo "Resetting project"
            rm -f "${toml_file}"
            uv init || { echo "Failed to run 'uv init'"; exit 1; }
        else
            echo "Project reset skipped"
        fi
    else
        uv init || { echo "Failed to run 'uv init'"; exit 1; }
    fi

    if [[ -f main.py ]]; then
        mkdir -p "src/${sub_dirname}"
        mv main.py "src/${sub_dirname}/entry.py"
        echo "Moved main.py to src/${sub_dirname}/entry.py"
        configure_project
        echo "Project initialization completed"
    else
        echo "main.py not found, skipping file move"
    fi

    echo "Running: uv run ${sub_dirname}"
    uv run "${sub_dirname}" || { echo "Failed to run 'uv run ${sub_dirname}'"; exit 1; }
}

# 添加 .gitignore 文件
add_gitignore() {
    if [[ ! -f .gitignore ]]; then
        echo "Creating .gitignore file"
        cat <<EOF > .gitignore
# Python-generated files
__pycache__/
*.py[oc]
build/
dist/
wheels/
*.egg-info

# Virtual environments
.venv

# IDE-specific files
.idea/
.vscode/
.marscode/
EOF
    else
        echo ".gitignore already exists, skipping creation"
    fi
}

# 主函数
main() {
    setup_directory_names
    create_readme
    init_project
    add_gitignore
}

main "$@"
