#!/bin/sh
#=====================================================================#
#	Couchbase Minishift Demo Management Tool
#		@Author - Craig Kovar
#		@Date - 10/20/2018
#		@Version - 1.0
#=====================================================================#

trap onError ERR

function onError
{
	echo "Error detected, exiting..."
	trap - ERR
	exit 1
}

function log
{
	echo "[$1]"	
}

function logSection
{
	echo ""
	echo "[$1]"
	echo ""
}


#Constants
VERSION=1.0.0
user="none"
status="Stopped"

if [ ! -f CB_Minishift.properties ];then
	log "Unable to locate property file CB_Minishift.properties"
	exit 1
else
	. ./CB_Minishift.properties
	
fi

#--------------------------------------------------------------#
#	Functions
#--------------------------------------------------------------#
function check_prereq
{
	logSection "Checking prereqs..."
	fail=0
	if  ! type brew > /dev/null;then
		fail=1
		log "Home Brew is not installed"
	else
		log "Home Brew	... passed"
	fi
	
	if  ! type wget > /dev/null;then
		fail=1
		log "wget is not installed"
	else
		log "wget	... passed"
	fi
	
	if  ! type docker > /dev/null;then
		fail=1
		log "docker is not installed"
	else
		log "docker	... passed"
	fi

	if  ! type virtualbox > /dev/null;then
		fail=1
		log "virtualbox is not installed"
	else
		log "virtualbox	... passed"
	fi

	if [ $fail -ge 1 ];then
		log "Prerequisites did not pass...."
		exit 1
	fi

}

function get_status
{
	logSection "Retrieving status...."
	status=`minishift status | grep Minishift | cut -d" " -f3`
	log "Current Status is : $status"
}

function errPass
{
	log "Checking OC status"
}

function update_operator_yaml
{
	logSection "Updating $OPERATORYAML to docker image"
	YAML=$OPERATORYAML
	if [ ! -f $OPERATORYAML ];then
		if [ -f ${SNAME}/${OPERATORYAML} ];then
			YAML=${SNAME}/${OPERATORYAML}
		fi
	fi

	sed -i .`date +%Y%m%d%H%M%S`  -e "s|        image: .*|        image: $OPERATOR_IMAGE|g" $YAML
}

function update_cluster_yaml
{
	logSection "Updating $CBCLUSTERYAML to docker image"
	YAML=$CBCLUSTERYAML
	if [ ! -f $CBCLUSTERYAML ];then
		if [ -f ${SNAME}/${CBCLUSTERYAML} ];then
			YAML=${SNAME}/${CBCLUSTERYAML}
		fi
	fi

	sed -i .`date +%Y%m%d%H%M%S`  -e "s|  baseImage: .*|  baseImage: $CB_IMAGE|g" -e "s|  version: .*|  version: $CB_VERSION|g" $YAML
}

function checkOC
{
	trap - ERR
	trap errPass ERR
	if  ! type oc > /dev/null;then
		log "OC command not registered, run . ./Install_Minishift.sh set_env"
		trap - ERR
		exit 1
	fi

	log "OC is registered"
	trap - ERR
	trap onError ERR
}

function set_env
{
	get_status
	if [ "$status" = "Running" ];then
		eval $(minishift oc-env)
		log "OC is registered"
	else
		log "Minishift not running..."
	fi
}

function install_core
{
	check_prereq

	#Install Minishift
	logSection "Installing minishift...."
	brew cask install minishift

	#Download CB Autonomous Operator for MacOS
	logSection "Downloading CB Autonomous Operator"
	wget ${W3_LOC}/${CBOP_NAME}

	#UNZIP CB OP
	logSection "Unzipping CB Autonomous Operator"
	log "Running: unzip -o $CBOP_NAME"
	unzip -o $CBOP_NAME
	if [ $? -gt 0 ];then
		echo "Unable to unzip file"
	else
		rm $CBOP_NAME
	fi

	#Change to directory
	#logSection "CDing to CB Operator Directory"
	#cd $SNAME
	#log "At directory:  `pwd`"

	#Starting Minishift
	logSection "Starting minishift...."
	minishift start --vm-driver=virtualbox --cpus $CPU_CNT --memory $MEMORY

	#Applying admin addon to minishift
	logSection "Applying minishift addon admin-user"
	minishift addon apply admin-user	

	#Set up OC command
	logSection "Setting up OC command"
	echo ""
	eval $(minishift oc-env)
}

function start_minishift
{
	logSection "Starting Minishift"

	get_status

	if [[ "$status" = "Stopped" || -z $status ]];then
		log "Starting minishift...."
		minishift start --vm-driver=virtualbox --cpus $CPU_CNT --memory $MEMORY
		
		log "Setting up OC command line"
        	eval $(minishift oc-env)
		
		log "Applying minishift addon admin-user"
		minishift addon apply admin-user	
	fi
}


function stopMinishift
{
	logSection "Stopping Minishift"
	get_status
	if [ "$status" = "Running" ];then
		log "Stopping minishift...."
		minishift stop
	fi
}

function create_project
{
	#Login as developer
	logSection "Creating an OpenShift Project"
	log "Logging in as Developer"
	oc logout
	oc login --insecure-skip-tls-verify -u developer <<< "developer"

	proj_cnt=`oc get project | grep -c ${OC_PROJ_NAME}`
	if [ $proj_cnt -gt 0 ];then
		log "Running: oc delete project ${OC_PROJ_NAME}"
		oc delete project ${OC_PROJ_NAME}
		sleep $SLEEP_DELAY
	fi

	log "Creating new project: $OC_PROJ_NAME"
	oc new-project ${OC_PROJ_NAME}

	#log "Logging out"
	#oc logout
}

function get_user
{
	logSection "Retrieving User...."
	log "Checking minishift status"
	get_status
	if [ "$status" = "Running" ];then
		user=`oc whoami | awk '{print $1}'`
		log "Current user is : $user"
	else
		log "Minishift is not running"
		exit 1
	fi
}

function install_crd
{
	logSection "Deploying Couchbase CRD"
	get_user
	if [ "$user" = "developer" ];then
		log "User [$user] has insufficient priveleges to install CRD, switching to admin"
		oc logout
		oc login --insecure-skip-tls-verify -u admin <<< "admin"
	fi

	#TODO add check if already deployed,  then remove and deploy
	crd_count=`oc get crd | grep -c "couchbaseclusters.couchbase.com"`
	
	if [ $crd_count -gt 0 ];then
		if [ -f $CRDYAML ];then
			log "Running: oc replace -f $CRDYAML"
			oc replace -f $CRDYAML
		elif [ -f $SNAME/$CRDYAML ];then
			log "Running: oc replace -f $SNAME/$CRDYAML"
			oc replace -f $SNAME/$CRDYAML
		else
			log "Unable to locate $CRDYAML, exiting..."
			exit 1
		fi
	else
		if [ -f $CRDYAML ];then
			log "Running: oc create -f $CRDYAML"
			oc create -f $CRDYAML
		elif [ -f $SNAME/$CRDYAML ];then
			log "Running: oc create -f $SNAME/$CRDYAML"
			oc create -f $SNAME/$CRDYAML
		else
			log "Unable to locate $CRDYAML, exiting..."
			exit 1
		fi
	fi
}

function create_rh_secret {
	logSection "Creating RedHat secret..."

	get_user
	if [ "$user" = "developer" ];then
                log "User [$user] has insufficient priveleges to install CRD, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi	

	sec_count=`oc get secret --namespace $OC_PROJ_NAME | grep -c "$RH_SECRET"`
	
	if [ "$status" = "Running" ];then
		if [ "$sec_count" -gt 0 ];then
			log "Running oc replace secret...."
			oc delete secret $RH_SECRET --namespace $OC_PROJ_NAME
			sleep $SLEEP_DELAY
			oc create secret docker-registry $RH_SECRET --docker-server=registry.connect.redhat.com \
 		 	--docker-username=$RH_USER --docker-password=$RH_PASSWORD --docker-email=$RH_EMAIL --namespace $OC_PROJ_NAME
		else
			log "Running oc create secret..."
			oc create secret docker-registry $RH_SECRET --docker-server=registry.connect.redhat.com \
 		 	--docker-username=$RH_USER --docker-password=$RH_PASSWORD --docker-email=$RH_EMAIL --namespace $OC_PROJ_NAME
		fi
	fi
}

function create_object {

	OBJECT=${1}
	NAMESPACE=${2}

	if [ "$status" = "Running" ];then
		if [ -f $OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: oc create -f $OBJECT -n $NAMESPACE"
				oc create -f $OBJECT -n $NAMESPACE
			else
				log "Running: oc create -f $OBJECT"
				oc create -f $OBJECT
			fi
		elif [ -f $SNAME/$OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: oc create -f $SNAME/$OBJECT -n $NAMESPACE"
				oc create -f $SNAME/$OBJECT -n $NAMESPACE
			else
				log "Running: oc create -f $SNAME/$OBJECT"
				oc create -f $SNAME/$OBJECT
			fi
		else
			log "Unable to locate $OBJECT"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function delete_object {

	OBJECT=${1}
	NAMESPACE=${2}

	if [ "$status" = "Running" ];then
		if [ -f $OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: oc delete -f $OBJECT -n $NAMESPACE"
				oc delete -f $OBJECT -n $NAMESPACE
			else
				log "Running: oc delete -f $OBJECT"
				oc delete -f $OBJECT
			fi
		elif [ -f $SNAME/$OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: oc delete -f $SNAME/$OBJECT -n $NAMESPACE"
				oc delete -f $SNAME/$OBJECT -n $NAMESPACE
			else
				log "Running: oc delete -f $SNAME/$OBJECT"
				oc delete -f $SNAME/$OBJECT
			fi
		else
			log "Unable to locate $OBJECT"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function kube_create_object {

	OBJECT=${1}
	NAMESPACE=${2}

	if [ "$status" = "Running" ];then
		if [ -f $OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: kubectl create -f $OBJECT -n $NAMESPACE"
				kubectl create -f $OBJECT -n $NAMESPACE
			else
				log "Running: kubectl create -f $OBJECT"
				kubectl create -f $OBJECT
			fi
		elif [ -f $SNAME/$OPERATORYAML ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: kubectl create -f $SNAME/$OBJECT -n $NAMESPACE"
				kubectl create -f $SNAME/$OBJECT -n $NAMESPACE
			else
				log "Running: kubectl create -f $SNAME/$OBJECT"
				kubectl create -f $SNAME/$OBJECT
			fi
		else
			log "Unable to locate $OBJECT"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function kube_delete_object {

	OBJECT=${1}
	NAMESPACE=${2}

	if [ "$status" = "Running" ];then
		if [ -f $OBJECT ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: kubectl delete -f $OBJECT -n $NAMESPACE"
				kubectl delete -f $OBJECT -n $NAMESPACE
			else
				log "Running: kubectl delete -f $OBJECT"
				kubectl delete -f $OBJECT
			fi
		elif [ -f $SNAME/$OPERATORYAML ];then
			if [ ! -z $NAMESPACE ];then
				log "Running: kubectl delete -f $SNAME/$OBJECT -n $NAMESPACE"
				kubectl delete -f $SNAME/$OBJECT -n $NAMESPACE
			else
				log "Running: kubectl delete -f $SNAME/$OBJECT"
				kubectl delete -f $SNAME/$OBJECT
			fi
		else
			log "Unable to locate $OBJECT"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function create_operator {
	logSection "Creating the operator"
	
	get_user
	if [ "$user" != "developer" ];then
                log "Switching from $user to developer"
                oc logout
                oc login --insecure-skip-tls-verify -u developer <<< "developer"
        fi
	
	if [ "$status" = "Running" ];then
		opcnt=`oc get deployments -l app=$OPERATOR_NAME --namespace $OC_PROJ_NAME | grep -c $OPERATOR_NAME`
		if [ "$opcnt" -gt 0 ];then
			log "Running: oc delete deployment -l app=$OPERATOR_NAME --namespace $OC_PROJ_NAME"
			oc delete deployment -l app=$OPERATOR_NAME --namespace $OC_PROJ_NAME
			sleep $SLEEP_DELAY
		fi

		if [ "$IMAGE_SOURCE" = "DOCKER" ];then
			update_operator_yaml
		elif [ "$IMAGE_SOURCE" = "REDHAT" ];then
			log "Image source = RedHat, nothing to do"
		else
			log "Unknown Image Source: $IMAGE_SOURCE, exiting..."
			exit 1
		fi

		if [ -f $OPERATORYAML ];then
			log "Running: oc create -f $OPERATORYAML -n $OC_PROJ_NAME"
			oc create -f $OPERATORYAML -n $OC_PROJ_NAME
		elif [ -f $SNAME/$OPERATORYAML ];then
			log "Running: oc create -f $SNAME/$OPERATORYAML -n $OC_PROJ_NAME"
			oc create -f $SNAME/$OPERATORYAML -n $OC_PROJ_NAME
		else
			log "Unable to locate $OPERATORYMAL"
			exit 1
		fi
	else
		log "Minishift is not running...."
		exit 1
	fi

	RETRY_CNT=1
	SUCC_CNT=0
	while [[ $SUCC_CNT -lt 1 && $RETRY_CNT -le $MAX_RETRY ]];do
		log "checking operator status... try $RETRY_CNT"
		SUCC_CNT=`oc get pods -l app=$OPERATOR_NAME | grep -c "1/1"`
		RETRY_CNT=$((RETRY_CNT+1))
		sleep $RETRY_DELAY
	done

	if [ $SUCC_CNT -lt 1 ];then
		log "Operator did not start..."
		exit 1
	fi
}

function create_cluster_role {
	logSection "Creating the cluster role"
	
	get_user
	if [ "$user" = "developer" ];then
                log "User [$user] has insufficient priveleges to install CRD, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get clusterroles | grep -c "$CLUSTER_ROLE_NAME"`
		if [ "$cr_count" -gt 0 ];then
			delete_object $CLUSTERROLEYAML
			sleep $SLEEP_DELAY
		fi
		create_object $CLUSTERROLEYAML
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function create_service_account {
	logSection "Creating the service account"
	
	get_user
	if [ "$user" = "developer" ];then
                log "User [$user] has insufficient priveleges to install CRD, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		sa_count=`oc get serviceaccounts --namespace $OC_PROJ_NAME | grep -c "$SVC_ACCOUNT"`
		if [ "$sa_count" -gt 0 ];then
			log "Running: oc delete serviceaccount $SVC_ACCOUNT --namespace $OC_PROJ_NAME"
			oc delete serviceaccount $SVC_ACCOUNT --namespace $OC_PROJ_NAME
			sleep $SLEEP_DELAY
		fi
		log "Running: oc create serviceaccount $SVC_ACCOUNT --namespace $OC_PROJ_NAME"
		oc create serviceaccount $SVC_ACCOUNT --namespace $OC_PROJ_NAME
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function bind_svc_account
{
	logSection "Binding the service account"

	get_user
	if [ "$user" = "developer" ];then
                log "User [$user] has insufficient priveleges to bind user, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		log "Running: oc secrets link serviceaccount/$SVC_ACCOUNT secrets/$RH_SECRET --for=pull --namespace=$OC_PROJ_NAME"
		oc secrets link serviceaccount/$SVC_ACCOUNT secrets/$RH_SECRET --for=pull --namespace=$OC_PROJ_NAME

		log "Running: oc secrets link serviceaccount/default secrets/$RH_SECRET --for=pull --namespace=$OC_PROJ_NAME"
		oc secrets link serviceaccount/default secrets/$RH_SECRET --for=pull --namespace=$OC_PROJ_NAME

		crb_count=`oc get clusterrolebinding | grep -c "$CB_ROLE_BINDING"`
		if [ "$crb_count" -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CB_ROLE_BINDING"
			oc delete clusterrolebinding $CB_ROLE_BINDING
			sleep $SLEEP_DELAY
		fi
		log "Running: oc create clusterrolebinding $CB_ROLE_BINDING --clusterrole $CLUSTER_ROLE_NAME --serviceaccount $OC_PROJ_NAME:$SVC_ACCOUNT"
		oc create clusterrolebinding $CB_ROLE_BINDING --clusterrole $CLUSTER_ROLE_NAME --serviceaccount $OC_PROJ_NAME:$SVC_ACCOUNT

		log "Running: oc adm policy add-scc-to-user anyuid system:serviceaccount:$OC_PROJ_NAME:$SVC_ACCOUNT"
		oc adm policy add-scc-to-user anyuid system:serviceaccount:$OC_PROJ_NAME:$SVC_ACCOUNT
	fi
		
}	


function create_user_role {
	logSection "Creating the user role"
	
	get_user
	if [ "$user" = "developer" ];then
                log "User [$user] has insufficient priveleges to install CRD, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get clusterroles | grep -c "$CLUSTER_USER_NAME"`
		if [ "$cr_count" -gt 0 ];then
			delete_object $USERROLEYAML
			sleep $SLEEP_DELAY
		fi
		create_object $USERROLEYAML
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function bind_user
{
	logSection "Binding the developer account"

	get_user
	if [ "$user" = "developer" ];then
                log "User [$user] has insufficient priveleges to bind user, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		
		crb_count=`oc get clusterrolebinding | grep -c "$CB_USER_BINDING"`
		if [ "$crb_count" -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CB_USER_BINDING"
			oc delete clusterrolebinding $CB_USER_BINDING
			sleep $SLEEP_DELAY
		fi

		log "Running: oc create clusterrolebinding $CB_USER_BINDING --clusterrole $CLUSTER_USER_NAME --user developer"
		oc create clusterrolebinding $CB_USER_BINDING --clusterrole $CLUSTER_USER_NAME --user developer

	fi
}

function install_cbopctl
{
	logSection "Installing cbopctl tool..."

	if [[ -f ./bin/cbopctl || -f ${SNAME}/bin/cbopctl ]];then
		if [ -f /usr/local/bin/cbopctl ];then
			log "Removing old cbopctl"
			sudo rm /usr/local/bin/cbopctl
		fi

		if [ -f ./bin/cbopctl ];then
			log "Installing ./bin/cbopctl"
			chmod +x ./bin/cbopctl
			sudo mv ./bin/cbopctl /usr/local/bin/cbopctl
		else
			log "Installing ${SNAME}/bin/cbopctl"
			chmod +x ${SNAME}/bin/cbopctl
			sudo mv ${SNAME}/bin/cbopctl /usr/local/bin/cbopctl
		fi
	fi
}

function create_secret {
	logSection "Creating the CB user secret"
	
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get secret | grep -c "$SECRET_NAME"`
		if [ "$cr_count" -gt 0 ];then
			delete_object $SECRETYAML
			sleep $SLEEP_DELAY
		fi
		create_object $SECRETYAML
	else
		log "Minishift is not running...."
		exit 1
	fi
}

function full_rollback
{
	logSection "Performing a full rollback"
	
	get_user
	if [ "$user" = "developer" ];then
                log "User [$user] has insufficient priveleges to bind user, switching to admin"
                oc logout
                oc login --insecure-skip-tls-verify -u admin <<< "admin"
        fi
	
	if [ "$status" = "Running" ];then
		log "Verifying project"
		oc project $OC_PROJ_NAME		

		log "Removing cluster"
		count=`oc get couchbaseclusters | grep -c $CLUSTER_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete couchbasecluster $CLUSTER_NAME"
			oc delete couchbasecluster $CLUSTER_NAME
		fi

		log "Removing route"
		count=`oc get routes | grep -c "${CLUSTER_NAME}-ui"`
		if [ $count -gt 0 ];then
			log "Running: oc delete route ${CLUSTER_NAME}-ui"
			oc delete route ${CLUSTER_NAME}-ui
		fi

		log "Removing secret"
		count=`oc get secrets | grep -c $SECRET_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete secret $SECRET_NAME"
			oc delete secret $SECRET_NAME
		fi
		
		log "Removing operator"
		count=`oc get deployments | grep -c $OPERATOR_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete deployment $OPERATOR_NAME"
			oc delete deployment $OPERATOR_NAME
		fi

		log "Removing developer cluster-role-binding"
		count=`oc get clusterrolebindings | grep -c $CB_USER_BINDING`
		if [ $count -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CB_USER_BINDING"
			oc delete clusterrolebinding $CB_USER_BINDING
		fi

		log "Removing user cluster role"
		count=`oc get clusterrole | grep -c $CLUSTER_USER_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CLUSTER_USER_NAME"
			oc delete clusterrole $CLUSTER_USER_NAME
		fi

		log "Removing SA cluster-role-binding"
		count=`oc get clusterrolebindings | grep -c $CB_ROLE_BINDING`
		if [ $count -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CB_ROLE_BINDING"
			oc delete clusterrolebinding $CB_ROLE_BINDING
		fi

		log "Removing SA cluster role"
		count=`oc get clusterrole | grep -c $CLUSTER_ROLE_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete clusterrolebinding $CLUSTER_ROLE_NAME"
			oc delete clusterrole $CLUSTER_ROLE_NAME
		fi

		
		log "Removing CRD"
		count=`oc get crd | grep -c "$CRD_NAME"`
		if [ $count -gt 0 ];then
			log "Running: oc delete crd $CRD_NAME"
			oc delete crd "$CRD_NAME"
		fi
		
		
		log "Removing Project"
		count=`oc get project | grep -c $OC_PROJ_NAME`
		if [ $count -gt 0 ];then
			log "Running: oc delete project $OC_PROJ_NAME"
			oc delete project $OC_PROJ_NAME
		fi
	
		stopMinishift	
	else
		log "Minishift not running"
	fi
}

function upsert_cluster
{
	logSection "Upserting couchbase cluster..."
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get couchbasecluster | grep -c "$CLUSTER_NAME"`
		
		if [ -f $CBCLUSTERYAML ];then
			CB_DEPLOY_NAME=$CBCLUSTERYAML
		elif [ -f ${SNAME}/${CBCLUSTERYAML} ];then
			CB_DEPLOY_NAME=${SNAME}/${CBCLUSTERYAML}
		else
			log "Unable to find $CBCLUSTERYAML..."
			exit 1
		fi
		
		if [ "$IMAGE_SOURCE" = "DOCKER" ];then
			update_cluster_yaml
		elif [ "$IMAGE_SOURCE" = "REDHAT" ];then
			log "Image source = RedHat, nothing to do"
		else
			log "Unknown Image Source: $IMAGE_SOURCE, exiting..."
			exit 1
		fi


		if [ "$cr_count" -gt 0 ];then
			log "Running: cbopctl apply -f $CB_DEPLOY_NAME"
			cbopctl apply -f $CB_DEPLOY_NAME
		else	
			log "Running: cbopctl create -f $CB_DEPLOY_NAME"
			cbopctl create -f $CB_DEPLOY_NAME
		fi
	else
		log "Minishift not running..."
		exit 1
	fi
}

function delete_cluster
{
	logSection "Deleting couchbase cluster..."
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get couchbasecluster | grep -c "$CLUSTER_NAME"`
		
		if [ -f $CBCLUSTERYAML ];then
			CB_DEPLOY_NAME=$CBCLUSTERYAML
		elif [ -f ${SNAME}/${CBCLUSTERYAML} ];then
			CB_DEPLOY_NAME=${SNAME}/${CBCLUSTERYAML}
		else
			log "Unable to find $CBCLUSTERYAML..."
			exit 1
		fi

		if [ "$cr_count" -gt 0 ];then
			log "Running: cbopctl delete -f $CB_DEPLOY_NAME"
			cbopctl delete -f $CB_DEPLOY_NAME
		else	
			log "No couchbase cluster named $CLUSTER_NAME detected..."
		fi
	else
		log "Minishift not running..."
		exit 1
	fi
}

function create_accounts
{
	logSection "Creating accounts"

	start_minishift

	create_rh_secret

	create_cluster_role

	create_service_account

	bind_svc_account

	create_user_role

	bind_user
}


function full_deploy
{
	logSection "Performing a full deployment"

	start_minishift

	create_project

	install_crd

	create_accounts

	create_operator	

	install_cbopctl

	create_secret

	upsert_cluster

	get_admin_ui

	log "\n\nCheck oc get pods for status of cluster deployment"
	
}	

function get_admin_ui
{
	logSection "Retrieving the admin UI location..."
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get routes | grep -c "${CLUSTER_NAME}-ui"`
		if [ "$cr_count" -gt 0 ];then
			log "Running: oc get routes | grep $CLUSTER_NAME | tr -s ' '| cut -d' ' -f2"
			log "	ADMIN URL:	`oc get routes | grep "$CLUSTER_NAME" | tr -s ' '| cut -d' ' -f2`	"
		else	
			log "Running: oc expose service/${CLUSTER_NAME}-ui"
			oc expose service/${CLUSTER_NAME}-ui
			sleep $SLEEP_DELAY
			log "Running: oc get routes | grep $CLUSTER_NAME | tr -s ' '| cut -d' ' -f2"
			log "	ADMIN URL:	`oc get routes | grep "$CLUSTER_NAME" | tr -s ' '| cut -d' ' -f2`	"
		fi
	else
		log "Minishift not running..."
		exit 1
	fi
}


function setup_s2i
{
	logSection "Setting up S2I for Java applications"
	get_status
	
	if [ "$status" = "Running" ];then
		log "Running: oc import-image registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift --confirm"
		oc import-image registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift --confirm
	else
		log "Minishift is not running"
	fi
}

function deploy_twitter_api
{
	logSection "Deploying twitter-api"
	get_status
	
	if [ "$status" = "Running" ];then

		count=`oc get svc | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Twitter API already deployed..."
			return 0
		fi

		log "\noc new-app registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:latest~https://github.com/couchbase-partners/redhat-pds.git \
			\n\t-e COUCHBASE_CLUSTER=$CLUSTER_NAME \
			\n\t-e COUCHBASE_USER=$CB_USER \
			\n\t-e COUCHBASE_PASSWORD=$CB_PASS \
			\n\t-e COUCHBASE_TWEET_BUCKET=$CB_TWEET_BUCKET \
			\n\t--context-dir=cb-rh-twitter/twitter-api \
			\n\t--name=twitter-api\n"

		oc new-app registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:latest~https://github.com/couchbase-partners/redhat-pds.git \
		-e COUCHBASE_CLUSTER=$CLUSTER_NAME \
		-e COUCHBASE_USER=$CB_USER \
		-e COUCHBASE_PASSWORD=$CB_PASS \
		-e COUCHBASE_TWEET_BUCKET=$CB_TWEET_BUCKET \
		--context-dir=cb-rh-twitter/twitter-api \
		--name=twitter-api

	
		sleep $BUILD_RETRY_DELAY	
		RETRY_CNT=1
		SUCC_CNT=`oc logs bc/twitter-api | grep -c "BUILD SUCCESS"`
		PUSH_CNT=`oc logs bc/twitter-api | grep -c "Push successful"`
		while [[ $PUSH_CNT -lt 1 && $SUCC_CNT -lt 1 && $RETRY_CNT -le $BUILD_RETRY ]];do
			log "checking twitter-api status... try $RETRY_CNT"
			SUCC_CNT=`oc logs bc/twitter-api | grep -c "BUILD SUCCESS"`
			PUSH_CNT=`oc logs bc/twitter-api | grep -c "Push successful"`
			RETRY_CNT=$((RETRY_CNT+1))
			sleep $BUILD_RETRY_DELAY
		done

		if [[ $SUCC_CNT -lt 1 || $PUSH_CNT -lt 1 ]];then
			log "Build Success = $SUCC_CNT"
			log "Pushi Success = $PUSH_CNT"
			log "Failed to build|push application"
			exit 1
		fi

		log "Exposing the twitter-api service:  oc expose svc twitter-api"
		oc expose svc twitter-api
	else
		log "Minishift is not running"
	fi
}

function remove_twitter_api
{
	logSection "Removing twitter-api"
	get_status
	
	if [ "$status" = "Running" ];then
		log "Removing twitter-api service"
		count=`oc get svc | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete svc twitter-api"
			oc delete svc twitter-api
		fi

		log "Removing twitter-api deploymentconfig"
		count=`oc get dc | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete dc twitter-api"
			oc delete dc twitter-api
		fi

		log "Removing twitter-api buildconfig"
		count=`oc get bc | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete bc twitter-api"
			oc delete bc twitter-api
		fi

		log "Removing twitter-api imagestream"
		count=`oc get is | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete is twitter-api"
			oc delete is twitter-api
		fi

		log "Removing twitter-api route"
		count=`oc get routes | grep -c twitter-api`
		if [ $count -eq 1 ];then
			log "Running: oc delete route twitter-api"
			oc delete route twitter-api
		fi

	fi
}

function deploy_twitter_ui
{
	logSection "Deploying twitter-ui"
	get_status

	if [ "$status" = "Running" ];then

		count=`oc get svc | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Twitter UI already deployed..."
			return 0
		fi

		log "Running: oc new-app ezeev/twitter-ui:latest"
		oc new-app ezeev/twitter-ui:latest

		log "Exposing the twitter-ui service:  oc expose svc twitter-ui"
		oc expose svc twitter-ui
	else
		log "Minishift is not running"
	fi
}

function remove_twitter_ui
{
	logSection "Removing twitter-ui"
	get_status
	
	if [ "$status" = "Running" ];then
		log "Removing twitter-ui service"
		count=`oc get svc | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete svc twitter-ui"
			oc delete svc twitter-ui
		fi

		log "Removing twitter-ui deploymentconfig"
		count=`oc get dc | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete dc twitter-ui"
			oc delete dc twitter-ui
		fi

		log "Removing twitter-ui buildconfig"
		count=`oc get bc | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete bc twitter-ui"
			oc delete bc twitter-ui
		fi

		log "Removing twitter-ui imagestream"
		count=`oc get is | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete is twitter-ui"
			oc delete is twitter-ui
		fi

		log "Removing twitter-ui route"
		count=`oc get routes | grep -c twitter-ui`
		if [ $count -eq 1 ];then
			log "Running: oc delete route twitter-ui"
			oc delete route twitter-ui
		fi

	fi
}

function get_twitter_ui
{
	logSection "Retrieving the twitter UI location..."
	get_status
	
	if [ "$status" = "Running" ];then
		cr_count=`oc get routes | grep -c "twitter-ui"`
		if [ "$cr_count" -gt 0 ];then
			log "Running: oc get routes | grep twitter-ui | tr -s ' '| cut -d' ' -f2"
			log "	ADMIN URL:	`oc get routes | grep twitter-ui | tr -s ' '| cut -d' ' -f2`	"
		fi
	else
		log "Minishift not running..."
		exit 1
	fi
}

function deploy_twitter_streamer
{
	logSection "Deploy twitter streamer"
	get_status

	if [ "$status" = "Running" ];then

		cr_count=`oc get svc | grep -c "twitter-streamer"`
		if [ $cr_count -eq 0 ];then
	
			log "\nRunning: oc new-app registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:latest~https://github.com/couchbase-partners/redhat-pds.git \
			\n\t-e TWITTER_CONSUMER_KEY=$TWITTER_CONSUMER_KEY \
			\n\t-e TWITTER_CONSUMER_SECRET=$TWITTER_CONSUMER_SECRET \
			\n\t-e TWITTER_TOKEN=$TWITTER_ACCESS_TOKEN \
			\n\t-e TWITTER_SECRET=$TWITTER_ACCESS_SECRET \
			\n\t-e TWITTER_FILTER='#RegisterToVote' \
			\n\t-e COUCHBASE_CLUSTER=$CLUSTER_NAME \
			\n\t-e COUCHBASE_USER=$CB_USER \
			\n\t-e COUCHBASE_PASSWORD=$CB_PASS \
			\n\t-e COUCHBASE_TWEET_BUCKET=$CB_TWEET_BUCKET \
			--context-dir=cb-rh-twitter/twitter-streamer \
			--name=twitter-streamer\n"		
	
			oc new-app registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:latest~https://github.com/couchbase-partners/redhat-pds.git \
      			 -e TWITTER_CONSUMER_KEY=$TWITTER_CONSUMER_KEY \
       			 -e TWITTER_CONSUMER_SECRET=$TWITTER_CONSUMER_SECRET \
       			 -e TWITTER_TOKEN=$TWITTER_ACCESS_TOKEN \
      			 -e TWITTER_SECRET=$TWITTER_ACCESS_SECRET \
      			 -e TWITTER_FILTER='#RegisterToVote' \
      			 -e COUCHBASE_CLUSTER=$CLUSTER_NAME \
      			 -e COUCHBASE_USER=$CB_USER \
      			 -e COUCHBASE_PASSWORD=$CB_PASS \
      			 -e COUCHBASE_TWEET_BUCKET=$CB_TWEET_BUCKET \
      			 --context-dir=cb-rh-twitter/twitter-streamer \
      			 --name=twitter-streamer
		

			sleep $BUILD_RETRY_DELAY	
			RETRY_CNT=1
			SUCC_CNT=`oc logs bc/twitter-streamer | grep -c "BUILD SUCCESS"`
			PUSH_CNT=`oc logs bc/twitter-streamer | grep -c "Push successful"`
			while [[ $PUSH_CNT -lt 1 && $SUCC_CNT -lt 1 && $RETRY_CNT -le $BUILD_RETRY ]];do
				log "checking twitter-streamer status... try $RETRY_CNT"
				SUCC_CNT=`oc logs bc/twitter-streamer | grep -c "BUILD SUCCESS"`
				PUSH_CNT=`oc logs bc/twitter-streamer | grep -c "Push successful"`
				RETRY_CNT=$((RETRY_CNT+1))
				sleep $BUILD_RETRY_DELAY
			done

			if [[ $SUCC_CNT -lt 1 || $PUSH_CNT -lt 1 ]];then
				log "Build Success = $SUCC_CNT"
				log "Pushi Success = $PUSH_CNT"
				log "Failed to build|push application"
				exit 1
			fi

			log "Exposing the twitter-streamer service:  oc expose svc twitter-streamer"
			oc expose svc twitter-streamer
		else
			log "Twitter Streamer already detected, run remove_twitter_streamer before re-deploying"
		fi
	else
		log "Minishift is not running"
	fi
}

function remove_twitter_streamer
{
	logSection "Removing twitter-streamer"
	get_status
	
	if [ "$status" = "Running" ];then
		log "Removing twitter-streamer service"
		count=`oc get svc | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete svc twitter-streamer"
			oc delete svc twitter-streamer
		fi

		log "Removing twitter-streamer deploymentconfig"
		count=`oc get dc | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete dc twitter-streamer"
			oc delete dc twitter-streamer
		fi

		log "Removing twitter-streamer buildconfig"
		count=`oc get bc | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete bc twitter-streamer"
			oc delete bc twitter-streamer
		fi

		log "Removing twitter-streamer imagestream"
		count=`oc get is | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete is twitter-streamer"
			oc delete is twitter-streamer
		fi

		log "Removing twitter-streamer route"
		count=`oc get routes | grep -c twitter-streamer`
		if [ $count -eq 1 ];then
			log "Running: oc delete route twitter-streamer"
			oc delete route twitter-streamer
		fi

	fi
}

function deploy_mysql
{
	logSection "Deploying MySQL DB"

	get_status

	if [ "$status" = "Running" ];then
		
		log "\n	oc new-app -e MYSQL_USER=$MYSQL_USER \
\n\t-e MYSQL_PASSWORD=$MYSQL_PASSWORD \
\n\t-e MYSQL_DATABASE=$MYSQL_DATABASE \
\n\t-e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
\n\topenshift/mysql-55-centos7\n"

		oc new-app -e MYSQL_USER=$MYSQL_USER \
-e MYSQL_PASSWORD=$MYSQL_PASSWORD \
-e MYSQL_DATABASE=$MYSQL_DATABASE \
-e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
openshift/mysql-55-centos7


	fi
}

function deploy_postgre
{
	logSection "Deploying PostGRE DB"

	get_status

	if [ "$status" = "Running" ];then
		
		log "\n	oc new-app -e POSTGRESQL_USER=$POSTGRESQL_USER \
\n\t-e POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD \
\n\t-e POSTGRESQL_DATABASE=$POSTGRESQL_DATABASE \
\n\topenshift/postgresql-92-centos7"


		oc new-app -e POSTGRESQL_USER=$POSTGRESQL_USER \
-e POSTGRESQL_PASSWORD=$POSTGRESQL_PASSWORD \
-e POSTGRESQL_DATABASE=$POSTGRESQL_DATABASE \
openshift/postgresql-92-centos7


	fi
}

function usage
{
	echo "Install_Minishift.sh [step 1] [step 2] ... [step N]"
	echo "Version :  $VERSIO"
	echo ""
	echo "	Steps: "
	echo "		install_core		--	Installs Minishift, downloads the CB Operator, Starts minishift and sets up the OC command"
	echo "		start_minishift		--	Starts Minishift"
	echo "		create_project		--	Creates an OpenShift Project"
	echo "		install_crd		--	Installs the Couchbase Custom Resource Definition"
	echo "		get_user			--	Returns the current logged in user"
	echo "		get_status		--	Returns the status of Minishift"
	echo "		create_rh_secret	--	Create a RedHat secret for access to RH Docker Images"
	echo "		create_operator		--	Create the CB Operator"
	echo "		create_cluster_role	--	Creates the cluster role for the service account"
	echo "		create_service_account	--	Creates the service account"
	echo "		bind_svc_account	--	Bind the service account to secret"
	echo "		create_user_role	--	Create the user role for developer"
	echo "		bind_user		--	Bind the developer account"
	echo "		install_cbopctl		--	Install cbopctl tool"
	echo "		create_secret		--	Create the CB Super User secret"
	echo "		upsert_cluster		--	Create or Apply a CB Cluster"
	echo "		delete_cluster		--	Delete the specified cluster"
	echo "		set_env			--	Set minishift oc-env"
	echo "		get_admin_ui		--	Get Admin UI URL"
	echo ""
	echo "	Composite Steps: "
	echo "		full_rollback		--	Perform a full_rollback of all Minishift components (no software uninstalled)"
	echo "		create_accounts		--	Creates all accounts and bindings by running the following steps"
	echo "							create_rh_secret"
	echo "							create_cluster_role"
	echo "							create_service_account"
	echo "							bind_svc_account"
	echo "							create_user_role"
	echo "							bind_user"
	echo ""	
	echo "		full_deploy		--	Perform a full deployment of OC components by running the following steps"
	echo "							create_project"
	echo "							install_crd"
	echo "							create_accounts"
	echo "							create_operator"
	echo "							install_cbopctl"
	echo "							create_secret"
	echo "							upsert_cluster"
	echo "	Twitter Application Steps: "
	echo "		setup_s2i		--	Sets up S2I for Java applications, necessary to run new-app build steps"
	echo "		deploy_twitter_api	--	Deploys the twitter-api java application"
	echo "		remove_twitter_api	--	Remove the twitter-api"
	echo "		deploy_twitter_ui	--	Deploy the twitter-ui java application"
	echo "		remove_twitter_ui	--	Remove the twitter_ui application"
	echo "		get_twitter_ui		--	Get twitter UI"
	echo "		deploy_twitter_streamer	--	Deploy the twitter streaming application"
	echo "		remove_twitter_streamer	--	Remove the twitter streaming application"
	echo ""
	echo "  Optional OC commands: "
	echo "		deploy_mysql		--	Deploys a MySQL DB"
	echo "		deploy_postgre		--	Deploys a PostGRE DB"
}


#=====================================================================#
#	Main Program
#=====================================================================#

clear

if [ "$#" -eq 0 ];then
	usage
fi

for var in "$@"
do
	case "$var" in
		-h|--help)
			usage
			break
			;;
		install_core)
			install_core
			;;
		start_minishift)
			start_minishift
			;;
		install_crd)
			checkOC
			install_crd
			;;
		get_user)
			checkOC
			get_user
			;;
		get_status)
			get_status
			;;
		create_rh_secret)
			checkOC
			create_rh_secret
			;;
		create_operator)
			checkOC
			create_operator
			;;
		create_cluster_role)
			checkOC
			create_cluster_role
			;;
		create_service_account)
			checkOC
			create_service_account
			;;
		bind_svc_account)
			checkOC
			bind_svc_account
			;;
		create_user_role)
			checkOC
			create_user_role
			;;
		bind_user)
			checkOC
			bind_user
			;;
		install_cbopctl)
			install_cbopctl
			;;
		create_secret)
			checkOC
			create_secret
			;;
		create_project)
			checkOC
			create_project
			;;
		create_accounts)
			checkOC
			create_accounts
			;;
		full_rollback)
			checkOC
			full_rollback
			;;
		set_env)
			set_env
			;;
		full_deploy)
			checkOC
			full_deploy
			;;
		checkOC)
			checkOC
			;;
		upsert_cluster)
			upsert_cluster
			;;
		delete_cluster)
			delete_cluster
			;;
		get_admin_ui)
			checkOC
			get_admin_ui
			;;
		setup_s2i)
			checkOC
			setup_s2i
			;;
		deploy_twitter_api)
			checkOC
			deploy_twitter_api
			;;
		remove_twitter_api)
			checkOC
			remove_twitter_api
			;;
		deploy_twitter_ui)
			checkOC
			deploy_twitter_ui
			;;
		remove_twitter_ui)
			checkOC
			remove_twitter_ui
			;;
		get_twitter_ui)
			checkOC
			get_twitter_ui
			;;
		deploy_twitter_streamer)
			checkOC
			deploy_twitter_streamer
			;;
		remove_twitter_streamer)
			checkOC
			remove_twitter_streamer
			;;
		deploy_mysql)
			checkOC
			deploy_mysql
			;;
		deploy_postgre)
			checkOC
			deploy_postgre
			;;
		*)
			log "Unknown command $var, ignoring..."
			;;
	esac
done

#Put some space before returning console to user
echo ""
echo ""

#Turn off trap
trap - ERR
