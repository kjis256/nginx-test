pipeline {
  agent any
  options { timestamps() }

  environment {
    // --- Git ---
    GIT_REPO_URL    = 'https://github.com/kjis256/nginx-test'
    GIT_BRANCH      = 'main'
    DOCKERFILE_PATH = 'Dockerfile'
    BUILD_CONTEXT   = '.'

    // --- AWS/ECR ---
    AWS_REGION  = 'ap-northeast-2'
    ACCOUNT_ID  = '193491250091'
    // 전체 경로 포함 이미지 이름
    ECR_IMAGE   = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/mybalance-stg/app"

    // --- 태그 정책 ---
    IMAGE_TAG   = "${env.BUILD_NUMBER}"
    LATEST_TAG  = "latest"

    // --- 배포 타깃(SSM: Name 태그) ---
    SSM_TARGETS = 'mybalance-stg-was-newapp01,mybalance-stg-was-newapp02'

    // --- 런타임 설정 ---
    SERVICE_NAME   = 'app'
    SERVICE_DIR    = '/srv/mybalance-app'
    CONTAINER_PORT = '80'
    HOST_PORT      = '80'
    TZ             = 'Asia/Seoul'
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: env.GIT_BRANCH, url: env.GIT_REPO_URL
      }
    }

    stage('Docker Build') {
      steps {
        sh '''
          docker build -f "${DOCKERFILE_PATH}" -t "${ECR_IMAGE}:${IMAGE_TAG}" "${BUILD_CONTEXT}"
          docker tag "${ECR_IMAGE}:${IMAGE_TAG}" "${ECR_IMAGE}:${LATEST_TAG}"
        '''
      }
    }

    stage('ECR Login & Push') {
      steps {
        sh '''
          aws ecr get-login-password --region "${AWS_REGION}" \
            | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

          docker push "${ECR_IMAGE}:${IMAGE_TAG}"
          docker push "${ECR_IMAGE}:${LATEST_TAG}"
        '''
      }
    }

stage('Deploy to EC2 via SSM') {
  steps {
    script {
      def targets = env.SSM_TARGETS.split(',')
      for (t in targets) {
        echo "Deploying to ${t} ..."

        // 100자 제한 대응: 짧은 코멘트 생성(길면 99자로 자름)
        def shortComment = "Deploy ${env.SERVICE_NAME}:${env.IMAGE_TAG} -> ${t}"
        if (shortComment.length() > 99) {
          shortComment = shortComment.take(99)
        }

        sh '''
          aws ssm send-command \
            --document-name "AWS-RunShellScript" \
            --comment "''' + shortComment + '''" \
            --targets "Key=tag:Name,Values=''' + t + '''" \
            --parameters commands=["set -euxo pipefail",\
"echo --- Deploying on \\$(hostname) ---",\
"aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com",\
"mkdir -p ${SERVICE_DIR}",\
"cd ${SERVICE_DIR}",\
"docker pull ${ECR_IMAGE}:${LATEST_TAG}",\
"(docker stop ${SERVICE_NAME} || true)",\
"(docker rm ${SERVICE_NAME} || true)",\
"docker run -d --name ${SERVICE_NAME} -p ${HOST_PORT}:${CONTAINER_PORT} -e TZ=${TZ} --restart always ${ECR_IMAGE}:${LATEST_TAG}",\
"docker image prune -f",\
"echo --- Deployment on \\$(hostname) complete ---"] \
            --max-errors 0 \
            --timeout-seconds 900 \
            --region "${AWS_REGION}" \
            --output text > /dev/null
        '''
      }
    }
  }
}

  }

  post {
    success {
      echo "✅ 성공: ${ECR_IMAGE}:${IMAGE_TAG} 배포 완료"
    }
    failure {
      echo "❌ 실패: 로그 확인 필요"
    }
    always {
      sh '''
        docker logout "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" || true
      '''
    }
  }
}
