pipeline {
  agent any
  options { timestamps() }

  environment {
    // --- Git ---
    GIT_REPO_URL   = 'https://github.com/kjis256/nginx-test'
    GIT_BRANCH     = 'main'
    DOCKERFILE_PATH = 'Dockerfile'
    BUILD_CONTEXT   = '.'

    // --- AWS/ECR ---
    AWS_DEFAULT_REGION = 'ap-northeast-2'
    // ⚠️ [제거] AWS_CREDS_ID 변수가 더 이상 필요 없습니다. (IAM Role 사용)
    ACCOUNT_ID         = '193491250091'
    ECR_IMAGE = "${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/mybalance-stg/app"

    // --- 태그 정책 ---
    IMAGE_TAG  = "${env.BUILD_NUMBER}"
    LATEST_TAG = "latest"

    // --- 배포 타깃(SSM: Name 태그) ---
    // (Terraform의 instance.tf 태그와 일치해야 함)
    SSM_TARGETS = 'mybalance-stg-was-newapp01,mybalance-stg-was-newapp02' // ⬅️ 'was-' 접두사 제거 (Terraform 태그 기준)

    // --- 원격 서버 런타임/Compose ---
    SERVICE_NAME   = 'app'
    SERVICE_DIR    = '/srv/mybalance-app' // ⬅️ 이전 단계에서 합의한 경로로 수정
    CONTAINER_PORT = '80'
    HOST_PORT      = '80'
    TZ = 'Asia/Seoul'
  }

  stages {
    stage('Checkout') {
      steps {
        // (Public Repo라 Credentials 불필요)
        git branch: env.GIT_BRANCH, url: env.GIT_REPO_URL
      }
    }

    stage('Docker Build') {
      steps {
        sh """
          docker build -f ${DOCKERFILE_PATH} -t ${ECR_IMAGE}:${IMAGE_TAG} ${BUILD_CONTEXT}
          docker tag ${ECR_IMAGE}:${IMAGE_TAG} ${ECR_IMAGE}:${LATEST_TAG}
        """
      }
    }

    stage('ECR Login & Push') {
      steps {
        // ⚠️ [수정] 'withAWS' 래퍼를 제거했습니다.
        // bs01 인스턴스의 IAM 역할(Role)이 자동으로 인증을 처리합니다.
        sh """
          aws ecr get-login-password --region ${AWS_DEFAULT_REGION} \
            | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com

          docker push ${ECR_IMAGE}:${IMAGE_TAG}
          docker push ${ECR_IMAGE}:${LATEST_TAG}
        """
      }
    }

    stage('Deploy to EC2 via SSM') {
      steps {
        script {
          def targets = env.SSM_TARGETS.split(',')
          for (t in targets) {
            echo "Deploying to ${t} ..."

            sh """
            aws ssm send-command \
              --document-name "AWS-RunShellScript" \
              --comment "Deploy ${ECR_IMAGE}:${IMAGE_TAG} to ${t}" \
              --targets "Key=tag:Name,Values=${t}" \
              --parameters '{
                "commands": [
                  "set -euxo pipefail",
                  "echo --- Deploying on \$(hostname) ---",

                  # 1) Docker 확인 및 재설치 (Amazon Linux 2023 기준)
                  "if ! command -v docker >/dev/null 2>&1; then",
                  "  sudo systemctl stop docker || true",
                  "  sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine docker-compose docker-compose-plugin containerd.io || true",
                  "  sudo yum install -y yum-utils",
                  "  sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo",
                  "  sudo sed -i 's/\\\\$releasever/9/g' /etc/yum.repos.d/docker-ce.repo",
                  "  sudo yum clean all && sudo yum makecache",
                  "  sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
                  "  sudo systemctl enable --now docker",
                  "  sudo usermod -aG docker ec2-user || true",
                  "fi",

                  # 2) ECR 로그인
                  "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com",

                  # 3) 서비스 디렉터리 준비
                  "sudo mkdir -p ${SERVICE_DIR}",
                  "sudo chown ec2-user:ec2-user ${SERVICE_DIR}",
                  "cd ${SERVICE_DIR}",

                  # 4) docker-compose.yml 자동 생성 (없을 경우)
                  "if [ ! -f docker-compose.yml ]; then",
                  "cat > docker-compose.yml <<'EOF'",
                  "version: '3.9'",
                  "services:",
                  "  ${SERVICE_NAME}:",
                  "    image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:latest",
                  "    restart: always",
                  "    ports:",
                  "      - '${HOST_PORT}:${CONTAINER_PORT}'",
                  "    environment:",
                  "      - TZ=${TZ}",
                  "EOF",
                  "fi",

                  # 5) 최신 이미지로 업데이트
                  "docker compose pull",
                  "docker compose up -d --remove-orphans",
                  "docker image prune -f",
                  "echo --- Deployment on \$(hostname) complete ---"
                ]
              }' \
              --max-errors 0 \
              --timeout-seconds 900 \
              --region ${AWS_REGION} \
              --output text > /dev/null
            """
          }
        }
      }
    }

  }

  post {
    success { echo "✅ 성공: ${ECR_IMAGE}:${IMAGE_TAG} 배포 완료" }
    failure { echo "❌ 실패: 로그 확인 필요" }
    always {
      // ECR 로그아웃 (보안)
      sh "docker logout ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
    }
  }
}