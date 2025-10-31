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
    AWS_CREDS_ID       = 'aws-ecr' // Jenkins Credentials ID
    ACCOUNT_ID         = '193491250091'
    // ECR 리포지토리 (Terraform의 ecr.tf에 맞춤)
    ECR_IMAGE = "${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/mybalance-stg/app"

    // --- 태그 정책 ---
    IMAGE_TAG  = "${env.BUILD_NUMBER}"  // BUILD_NUMBER 사용
    LATEST_TAG = "latest"

    // --- 배포 타깃(SSM: Name 태그) ---
    SSM_TARGETS = 'mybalance-stg-was-newapp01,mybalance-stg-was-newapp02'

    // --- 원격 서버 런타임/Compose ---
    SERVICE_NAME   = 'app'
    SERVICE_DIR    = '/opt/app'
    CONTAINER_PORT = '80'
    HOST_PORT      = '80'

    // --- 평문 환경변수 ---
    TZ = 'Asia/Seoul'
  }

  stages {
    stage('Checkout') {
      steps {
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
        withAWS(region: env.AWS_DEFAULT_REGION, credentials: env.AWS_CREDS_ID) {
          sh """
            aws ecr get-login-password --region ${AWS_DEFAULT_REGION} \
              | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com

            docker push ${ECR_IMAGE}:${IMAGE_TAG}
            docker push ${ECR_IMAGE}:${LATEST_TAG}
          """
        }
      }
    }

    stage('Deploy to EC2 via SSM') {
      steps {
        script {
          def targets = env.SSM_TARGETS.split(',').collect { it.trim() }.findAll { it }
          for (t in targets) {
            withAWS(region: env.AWS_DEFAULT_REGION, credentials: env.AWS_CREDS_ID) {
              sh """
                aws ssm send-command \
                  --document-name "AWS-RunShellScript" \
                  --comment "Deploy ${ECR_IMAGE}:${IMAGE_TAG} to ${t}" \
                  --targets "Key=tag:Name,Values=${t}" \
                  --parameters commands='[
                    "set -e",
                    // 1) Docker/Compose 설치 및 기동 (Amazon Linux 2023 우선, 없으면 Debian/Ubuntu 분기)
                    "if command -v dnf >/dev/null 2>&1; then sudo dnf -y install docker docker-compose-plugin || true; sudo systemctl enable --now docker; else sudo apt-get update -y; sudo apt-get install -y docker.io docker-compose-plugin; sudo systemctl enable --now docker; fi",
                    // 2) ECR 로그인
                    "aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com",
                    // 3) 서비스 디렉터리/Compose 파일 생성(없을 때만)
                    "sudo mkdir -p ${SERVICE_DIR} && cd ${SERVICE_DIR}",
                    "if [ ! -f docker-compose.yml ]; then cat > docker-compose.yml <<'EOF'\\nversion: \\"3.9\\"\\nservices:\\n  ${SERVICE_NAME}:\\n    image: ${ECR_IMAGE}:${LATEST_TAG}\\n    restart: always\\n    ports:\\n      - \\"${HOST_PORT}:${CONTAINER_PORT}\\"\\n    environment:\\n      - TZ=${TZ}\\nEOF\\nfi",
                    // 4) 최신 이미지 풀 & 재기동
                    "docker compose pull",
                    "docker compose up -d"
                  ]' \
                  --max-errors 0 \
                  --timeout-seconds 900 \
                  --output text >/dev/null
              """
            }
          }
        }
      }
    }
  }

  post {
    success { echo "✅ 성공: ${ECR_IMAGE}:${IMAGE_TAG} 배포 완료" }
    failure { echo "❌ 실패: 로그 확인 필요" }
  }
}
