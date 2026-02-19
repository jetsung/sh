#!/usr/bin/env bash

#============================================================
# File: deb2rpm.sh
# Description: 将 deb 包转换为 rpm 包
# URL: https://fx4.cn/deb2rpm
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.1.0
# CreatedAt: 2026-02-19
# UpdatedAt: 2026-02-19
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
    set -eux
else
    set -euo pipefail
fi

deb_path="$1"
extract_dir="$2"

if [[ ! -f "$deb_path" ]]; then
    echo "Error: deb file not found: $deb_path"
    exit 1
fi

if [[ -z "$extract_dir" ]]; then
    echo "Error: extract directory not specified"
    exit 1
fi

mkdir -p "$extract_dir"

# 提取 deb 包内容
echo "Extracting deb package..."
dpkg-deb -x "$deb_path" "$extract_dir"

# 提取控制信息
echo "Extracting control information..."
control_dir="$extract_dir/DEBIAN"
mkdir -p "$control_dir"
dpkg-deb -e "$deb_path" "$control_dir"

# 解析 control 文件
control_file="$control_dir/control"
if [[ ! -f "$control_file" ]]; then
    echo "Error: control file not found"
    exit 1
fi

# 读取包信息
pkg_name=$(grep -i "^Package:" "$control_file" | cut -d: -f2 | tr -d ' ')
pkg_version=$(grep -i "^Version:" "$control_file" | cut -d: -f2 | tr -d ' ')
pkg_arch=$(grep -i "^Architecture:" "$control_file" | cut -d: -f2 | tr -d ' ')
pkg_maintainer=$(grep -i "^Maintainer:" "$control_file" | cut -d: -f2- | sed 's/^ *//')
pkg_homepage=$(grep -i "^Homepage:" "$control_file" | cut -d: -f2- | sed 's/^ *//' | tr -d ' ')
# Description 可能有多行，只取第一行作为摘要
pkg_summary=$(grep -i "^Description:" "$control_file" | sed 's/^[Dd]escription:[[:space:]]*//' | head -1)

# 架构映射 (deb -> rpm)
case "$pkg_arch" in
    amd64)  rpm_arch="x86_64" ;;
    i386)   rpm_arch="i686" ;;
    arm64)  rpm_arch="aarch64" ;;
    armhf)  rpm_arch="armhfp" ;;
    *)      rpm_arch="$pkg_arch" ;;
esac

echo "Package: $pkg_name"
echo "Version: $pkg_version"
echo "Architecture: $pkg_arch -> $rpm_arch"

# 创建 RPM 构建目录
rpm_build_dir="$extract_dir/rpmbuild"
mkdir -p "$rpm_build_dir/BUILD"
mkdir -p "$rpm_build_dir/RPMS/x86_64"
mkdir -p "$rpm_build_dir/SOURCES"
mkdir -p "$rpm_build_dir/SPECS"
mkdir -p "$rpm_build_dir/SRPMS"

# 复制提取的文件到 BUILD 目录 (排除 DEBIAN 和 rpmbuild 目录)
build_root="$rpm_build_dir/BUILD/$pkg_name"
mkdir -p "$build_root"
find "$extract_dir" -mindepth 1 -maxdepth 1 ! -name "DEBIAN" ! -name "rpmbuild" -exec cp -r {} "$build_root/" \;

# 生成 %files 列表
files_list=""
while IFS= read -r file; do
    # 将绝对路径转换为 RPM 路径
    rpm_path="${file#"$build_root"}"
    if [[ -d "$file" ]]; then
        files_list+="%dir $rpm_path"$'\n'
    else
        files_list+="$rpm_path"$'\n'
    fi
done < <(find "$build_root" -mindepth 1 | sort)

# 生成 spec 文件
spec_file="$rpm_build_dir/SPECS/$pkg_name.spec"
changelog_date=$(LC_TIME=C date +"%a %b %d %Y")
cat > "$spec_file" << EOF
Name:           $pkg_name
Version:        $pkg_version
Release:        1%{?dist}
Summary:        $pkg_summary
License:        Unknown
URL:            ${pkg_homepage:-https://example.com}
Source0:        %{name}-%{version}.tar.gz
BuildArch:      $rpm_arch
# 禁用 debuginfo 包
%global debug_package %{nil}

%description
${pkg_summary:-No description provided}

%prep
%setup -q -n $pkg_name

%install
mkdir -p %{buildroot}
cp -r * %{buildroot}/

%files
%defattr(-,root,root)
$files_list

%changelog
* $changelog_date ${pkg_maintainer:-Unknown} - $pkg_version
- Initial package
EOF

echo "Spec file created: $spec_file"

# 获取绝对路径
rpm_build_dir_abs=$(cd "$extract_dir" && pwd)/rpmbuild
spec_file="$rpm_build_dir_abs/SPECS/$pkg_name.spec"

# 创建源码包
echo "Creating source tarball..."
cd "$rpm_build_dir_abs/BUILD"
tar czf "$rpm_build_dir_abs/SOURCES/$pkg_name-$pkg_version.tar.gz" "$pkg_name"

# 构建 RPM
echo "Building RPM package..."
cd "$rpm_build_dir_abs"
rpmbuild -bb --define "_topdir $rpm_build_dir_abs" "$spec_file"

# 输出结果
rpm_file=$(find "$rpm_build_dir_abs/RPMS" -name "*.rpm" -type f | head -1)
if [[ -n "$rpm_file" && -f "$rpm_file" ]]; then
    echo ""
    echo "RPM package created successfully!"
    echo "Output: $rpm_file"
else
    echo "Error: RPM build failed"
    exit 1
fi
