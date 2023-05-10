pipeline {
    agent any
    tools {
        terraform 'terraform'
    }
    stages {
        stage('Git Checkout'){
            steps{
                git branch: 'main', credentialsId: 'github', url: 'https://github.com/DhruvaSharma/terraform_jenkins.git'
            }
        }
        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }
        stage('Terraform Apply') {
            steps {
                sh 'terraform apply --auto-approve'
            }
        }
    }
}
