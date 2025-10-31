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
    SSM_TARGETS = 'mybalance-stg-newapp01,mybalance-stg-newapp02' // ⬅️ 'was-' 접두사 제거 (Terraform 태그 기준)

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
          def targets = env.SSM_TARGETS.split(',').collect { it.trim() }.findAll { it }
          for (t in targets) {
            
            // ⚠️ [수정] 'withAWS' 래퍼를 제거했습니다.
            // bs01 인스턴스의 IAM 역할(Role)이 자동으로 인증을 처리합니다.
            // (bs01 역할에 ssm:SendCommand 권한이 필요합니다.)
            sh """
              aws ssm send-command \
                --document-name "AWS-RunShellScript" \
                --comment "Deploy ${ECR_IMAGE}:${IMAGE_TAG} to ${t}" \
                --targets "Key=tag:Name,Values=${t}" \
                --parameters commands='[
                  "set -e",
                  "echo --- Deploying on \$(hostname) ---",
                  
                  // 1) Docker/Compose 설치 (Ubuntu/Debian)
                  "if ! command -v docker >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y docker.io docker-compose-plugin && sudo systemctl enable --now docker && sudo usermod -aG docker ubuntu; fi",
                  
                  // 2) ECR 로그인 (대상 서버의 IAM Role이 ECR Pull 권한 필요)
                  "aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com",
                  
                  // 3) 서비스 디렉터리/Compose 파일 생성(없을 때만)
                  "sudo mkdir -p ${SERVICE_DIR} && sudo chown ubuntu:ubuntu ${SERVICE_DIR} && cd ${SERVICE_DIR}",
                  "if [ ! -f docker-compose.yml ]; then cat > docker-compose.yml <<EOF\\nversion: \\"3.9\\"\\nservices:\\n  ${SERVICE_NAME}:\\n    image: ${ECR_IMAGE}:${LATEST_TAG}\\n    restart: always\\n    ports:\\n      - \\"${HOST_PORT}:${CONTAINER_PORT}\\"\\n    environment:\\n      - TZ=${TZ}\\nEOF\\nfi",
                  
                  // 4) 최신 이미지 풀 & 재기동
                  "docker compose pull",
                  "docker compose up -d --remove-orphans",
                  "echo --- Deployment on \$(hostname) complete ---"
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

  post {
    success { echo "✅ 성공: ${ECR_IMAGE}:${IMAGE_TAG} 배포 완료" }
    failure { echo "❌ 실패: 로그 확인 필요" }
    always {
      // ECR 로그아웃 (보안)
      sh "docker logout ${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
    }
  }
}