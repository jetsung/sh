#!/usr/bin/env bash

#============================================================
# File: $(basename "$0")
# Description: OpenCode 配置管理工具 - 管理 provider 和模型配置
#   - data: 从 base-aiurl.sh 提取 BASE_URL 并同步到 opencode.json
#   - model: 添加/清除/获取 provider 的模型列表
#   - show: 显示 provider 的模型信息或 JSON 配置
#   - copy: 复制 opencode 配置到 kilo 并更新 schema
# URL: https://fx4.cn/ochelp
# Author: Jetsung Chan <i@jetsung.com>
# Version: 0.2.0
# CreatedAt: 2026-03-05
# UpdatedAt: 2026-07-02
#============================================================

if [[ -n "${DEBUG:-}" ]]; then
  set -eux
else
  set -euo pipefail
fi

CONFIG_FILE="$HOME/.config/opencode/opencode.json"
CONFIG_FILE_KILO="$HOME/.config/kilo/opencode.json"
AI_BASE_FILE="$HOME/.envs/base-aiurl.sh"

# 帮助信息
show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -a, --action ACTION       Action to perform: 'data', 'model', 'show' or 'copy'
  -p, --provider PROVIDER   Provider name (for 'show' or 'model')
  -m, --model MODELS        Models to add (comma-separated, file path, or single model)
                            If not specified with 'model' action, clears models
  -M, --mode MODE           Mode for 'model' action: 'append' (default) or 'new'
  -j, --json                With -a show, output full JSON data instead of model list
  -f, --fetch               With -a model, fetch models from provider's API
  -h, --help               Show this help message

Examples:
  # Update all providers from base-aiurl.sh
  $(basename "$0") -a data

  # Show all models for all providers
  $(basename "$0") -a show

  # Show models for a specific provider
  $(basename "$0") -a show -p newapi

  # Show full JSON for all providers
  $(basename "$0") -a show -j

  # Show full JSON for a provider
  $(basename "$0") -a show -p newapi -j

  # Add models from comma-separated list (append by default)
  $(basename "$0") -a model -p newapi -m "glm4.7,glm4.6"

  # Overwrite with new models
  $(basename "$0") -a model -p newapi -m "glm4.7" -M new

  # Add models with provider prefix
  $(basename "$0") -a model -p newapi -m "nvidia/glm-4.7,iflow/glm4.6"

  # Add single model
  $(basename "$0") -a model -p newapi -m glm4.7

  # Add models from file (one per line)
  $(basename "$0") -a model -p newapi -m models.txt

  # Clear all models for a provider
  $(basename "$0") -a model -p newapi

  # Fetch models from provider's API
  $(basename "$0") -a model -p newapi -f

  # Copy opencode config to kilo and update schema
  $(basename "$0") -a copy

EOF
}

# 参数处理
ACTION=""
PROVIDER=""
MODELS=""
MODE="append"
JSON_MODE=false
FETCH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    show_help
    exit 0
    ;;
  -a | --action)
    ACTION="$2"
    shift 2
    ;;
  -p | --provider)
    PROVIDER="$2"
    shift 2
    ;;
  -m | --model)
    MODELS="$2"
    shift 2
    ;;
  -M | --mode)
    MODE="$2"
    shift 2
    ;;
  -j | --json)
    JSON_MODE=true
    shift 1
    ;;
  -f | --fetch)
    FETCH=true
    shift 1
    ;;
  *)
    echo "Unknown option: $1"
    show_help
    exit 1
    ;;
  esac
done

# 验证参数
if [[ -z "$ACTION" ]]; then
  echo "Error: --action (-a) is required"
  exit 1
fi

if [[ "$ACTION" != "data" && "$ACTION" != "model" && "$ACTION" != "show" && "$ACTION" != "copy" ]]; then
  echo "Error: Invalid action '$ACTION'. Must be 'data', 'model', 'show' or 'copy'"
  exit 1
fi

if [[ "$JSON_MODE" == true && "$ACTION" != "show" ]]; then
  echo "Error: --json (-j) is only valid with -a show"
  exit 1
fi

if [[ "$FETCH" == true ]]; then
  if [[ "$ACTION" != "model" && "$ACTION" != "show" ]]; then
    echo "Error: --fetch (-f) is only valid with -a model or -a show"
    exit 1
  fi
  if [[ -z "$PROVIDER" ]]; then
    echo "Error: --provider (-p) is required with --fetch (-f)"
    exit 1
  fi
fi

if [[ "$ACTION" == "show" ]]; then
  if [[ -z "$PROVIDER" && "$JSON_MODE" == false ]]; then
    # 无 provider 时默认显示全部，无需额外校验
    :
  fi
fi

if [[ "$ACTION" == "model" ]]; then
  if [[ -z "$PROVIDER" ]]; then
    echo "Error: --provider is required when --action is 'model'"
    exit 1
  fi
  if [[ "$MODE" != "append" && "$MODE" != "new" ]]; then
    echo "Error: Invalid mode '$MODE'. Must be 'append' or 'new'"
    exit 1
  fi
fi

# 处理 copy action
if [[ "$ACTION" == "copy" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: $CONFIG_FILE not found"
    exit 1
  fi

  mkdir -p "$HOME/.config/kilo"
  cp "$CONFIG_FILE" "$CONFIG_FILE_KILO"
  jq '."$schema" = "https://app.kilo.ai/config.json"' "$CONFIG_FILE_KILO" >"$CONFIG_FILE_KILO.tmp"
  mv "$CONFIG_FILE_KILO.tmp" "$CONFIG_FILE_KILO"

  echo "✓ Copied to kilo and updated schema"
  exit 0
fi

# 检查 CONFIG_FILE 存在
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: $CONFIG_FILE not found"
  exit 1
fi

# 处理 show action
if [[ "$ACTION" == "show" ]]; then
  if [[ "$FETCH" == true ]]; then
    base_url_raw=$(jq -r '.provider."'"$PROVIDER"'".options.baseURL // ""' "$CONFIG_FILE")
    api_key_raw=$(jq -r '.provider."'"$PROVIDER"'".options.apiKey // ""' "$CONFIG_FILE")

    if [[ -z "$base_url_raw" ]]; then
      echo "Error: Provider '$PROVIDER' not found in config"
      exit 1
    fi

    base_url_var=""; api_key_var=""
    [[ "$base_url_raw" =~ ^\{env:(.*)\}$ ]] && base_url_var="${BASH_REMATCH[1]}"
    [[ "$api_key_raw" =~ ^\{env:(.*)\}$ ]] && api_key_var="${BASH_REMATCH[1]}"

    base_url="${!base_url_var:-}"
    api_key_value="${!api_key_var:-}"

    if [[ -z "$base_url" ]]; then
      echo "Error: $base_url_var is not set"
      exit 1
    fi

    echo "Fetching models from $base_url/models..." >&2

    if [[ -z "$api_key_value" ]]; then
      echo "⚠ Warning: $api_key_var not set" >&2
    else
      mapfile -t model_ids < <(curl -s --max-time 15 -H "Authorization: Bearer $api_key_value" "$base_url/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null || true)
      printf '%s\n' "${model_ids[@]}"
    fi
    exit 0
  fi

  if [[ "$JSON_MODE" == true ]]; then
    if [[ -n "$PROVIDER" ]]; then
      jq ".provider.\"$PROVIDER\"" "$CONFIG_FILE"
    else
      jq ".provider" "$CONFIG_FILE"
    fi
  else
    if [[ -n "$PROVIDER" ]]; then
      jq -r '.provider."'"$PROVIDER"'" // empty | .models // {} | keys[]' "$CONFIG_FILE" 2>/dev/null || echo "  (no models or provider not found)"
    else
      jq -r '.provider | to_entries[] | .key as $p | .value.models // {} | keys[]' "$CONFIG_FILE" 2>/dev/null || echo "  (no models found)"
    fi
  fi
  exit 0
fi

# 处理 model action
if [[ "$ACTION" == "model" ]]; then
  if [[ "$FETCH" == true ]]; then
    base_url_raw=$(jq -r '.provider."'"$PROVIDER"'".options.baseURL // ""' "$CONFIG_FILE")
    api_key_raw=$(jq -r '.provider."'"$PROVIDER"'".options.apiKey // ""' "$CONFIG_FILE")

    if [[ -z "$base_url_raw" ]]; then
      echo "Error: Provider '$PROVIDER' not found in config"
      exit 1
    fi

    base_url_var=""; api_key_var=""
    [[ "$base_url_raw" =~ ^\{env:(.*)\}$ ]] && base_url_var="${BASH_REMATCH[1]}"
    [[ "$api_key_raw" =~ ^\{env:(.*)\}$ ]] && api_key_var="${BASH_REMATCH[1]}"

    base_url="${!base_url_var:-}"
    api_key_value="${!api_key_var:-}"

    if [[ -z "$base_url" ]]; then
      echo "Error: $base_url_var is not set"
      exit 1
    fi

    echo "Fetching models from $base_url/models..."

    if [[ -z "$api_key_value" ]]; then
      echo "⚠ Warning: $api_key_var not set, models set to empty"
      models_json="{}"
    else
      mapfile -t model_ids < <(curl -s --max-time 15 -H "Authorization: Bearer $api_key_value" "$base_url/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null || true)

      if [[ ${#model_ids[@]} -eq 0 ]]; then
        models_json="{}"
      else
        models_json="{}"
        for model_id in "${model_ids[@]}"; do
          if [[ "$model_id" == *"/"* ]]; then
            family="${model_id%%/*}"
            model_name="$model_id"
          else
            family="$PROVIDER"
            model_name="$family/$model_id"
          fi
          model_entry="{\"id\":\"$model_id\",\"name\":\"$model_name\",\"family\":\"$family\"}"
          models_json=$(echo "$models_json" | jq ".\"$model_name\" = $model_entry")
        done
      fi
    fi

    jq ".provider.\"$PROVIDER\".models = $models_json" "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

    echo "✓ Fetched and updated models for $PROVIDER"
    exit 0
  fi

  if [[ -z "$MODELS" ]] || [[ "$MODE" == "new" ]]; then
    # 清空 models 或重新添加模式
    models_json="{}"
  else
    # 追加模式：读取现有模型
    models_json=$(jq -c ".provider.\"$PROVIDER\".models // {}" "$CONFIG_FILE")
  fi

  if [[ -n "$MODELS" ]]; then
    # 判断是文件还是模型列表
    if [[ "$MODELS" == *","* ]]; then
      # 包含逗号，则是模型列表
      IFS=',' read -ra model_array <<<"$MODELS"
    elif [[ -f "$MODELS" ]]; then
      # 不包含逗号且文件存在，则是文件
      mapfile -t model_array <"$MODELS"
    else
      # 单个模型
      model_array=("$MODELS")
    fi

    for model_id in "${model_array[@]}"; do
      model_id="${model_id// /}" # 移除空格
      [[ -z "$model_id" ]] && continue

      # 检查是否包含 /
      if [[ "$model_id" == *"/"* ]]; then
        family="${model_id%%/*}"
        model_name="$model_id"
      else
        family="$PROVIDER"
        model_name="$family/$model_id"
      fi

      model_entry="{\"id\":\"$model_id\",\"name\":\"$model_name\",\"family\":\"$family\"}"
      models_json=$(echo "$models_json" | jq ".\"$model_name\" = $model_entry")
    done
  fi

  # 更新配置文件中的 models
  jq ".provider.\"$PROVIDER\".models = $models_json" "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

  if [[ -z "$MODELS" ]]; then
    echo "✓ Cleared models for $PROVIDER"
  else
    echo "✓ Updated models for $PROVIDER"
  fi
  exit 0
fi

# 检查 AI_BASE_FILE（仅 data action 需要）
if [[ ! -f "$AI_BASE_FILE" ]]; then
  echo "Error: $AI_BASE_FILE not found"
  exit 1
fi

# 提取所有 BASE_URL 环境变量
declare -A services
while IFS='=' read -r key value; do
  if [[ $key =~ ^export\ ([A-Z_]+)_BASE_URL$ ]]; then
    service_name="${BASH_REMATCH[1]}"
    service_lower=$(echo "$service_name" | tr '[:upper:]' '[:lower:]')

    # 移除引号
    value="${value%\"}"
    value="${value#\"}"
    services[$service_lower]="$value"
  fi
done <"$AI_BASE_FILE"

# 处理每个服务
for service in "${!services[@]}"; do
  base_url="${services[$service]}"
  api_key_var="${service^^}_API_KEY"

  echo "Processing: $service"

  # 检查服务是否已存在
  existing=$(jq -r ".provider.\"$service\" // empty" "$CONFIG_FILE")

  if [[ -n "$existing" ]]; then
    REPLY=""
    read -r -p "Service '$service' already exists. Overwrite? (y/n) " REPLY
    REPLY="${REPLY:0:1}"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Skipping $service"
      continue
    fi
  fi

  # 获取模型列表
  echo "Fetching models from $base_url/models..."
  api_key_value="${!api_key_var:-}"

  if [[ -z "$api_key_value" ]]; then
    echo "⚠ Warning: $api_key_var not set, skipping model fetch"
    models_json="{}"
  else
    # 先获取所有模型 ID
    mapfile -t model_ids < <(curl -s --max-time 15 -H "Authorization: Bearer $api_key_value" "$base_url/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null || true)

    model_count=${#model_ids[@]}

    if [[ $model_count -eq 0 ]]; then
      models_json="{}"
    else
      # 确认是否添加
      if [[ $model_count -le 10 ]]; then
        echo "✓ Found $model_count models, adding automatically"
        add_models=true
      else
        REPLY=""
        read -r -p "Found $model_count models. Add to config? (y/n) " REPLY
        REPLY="${REPLY:0:1}"
        add_models=false
        [[ $REPLY =~ ^[Yy]$ ]] && add_models=true
      fi

      # 组合模型数据
      if [[ "$add_models" == true ]]; then
        models_json="{}"
        for model_id in "${model_ids[@]}"; do
          # 检查是否包含 /
          if [[ "$model_id" == *"/"* ]]; then
            family="${model_id%%/*}"
            model_name="$model_id"
          else
            family="$service"
            model_name="$family/$model_id"
          fi

          model_entry="{\"id\":\"$model_id\",\"name\":\"$model_name\",\"family\":\"$family\"}"
          models_json=$(echo "$models_json" | jq ".\"$model_name\" = $model_entry")
        done
      else
        models_json="{}"
      fi
    fi
  fi

  # 构建服务配置
  service_config=$(
    cat <<EOF
{
    "name": "${service^} Custom",
    "id": "$service",
    "npm": "@ai-sdk/openai-compatible",
    "models": $models_json,
    "options": {
        "apiKey": "{env:${api_key_var}}",
        "baseURL": "{env:${service^^}_BASE_URL}"
    }
}
EOF
  )

  # 更新配置文件并复制到 kilo 目录
  jq ".provider.\"$service\" = $service_config" "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

  # 复制到 kilo 目录并更新 schema
  cp "$CONFIG_FILE" "$CONFIG_FILE_KILO"
  jq '."$schema" = "https://app.kilo.ai/config.json"' "$CONFIG_FILE_KILO" >"$CONFIG_FILE_KILO.tmp"
  mv "$CONFIG_FILE_KILO.tmp" "$CONFIG_FILE_KILO"

  echo "✓ Updated $service"
done

echo "Done!"
