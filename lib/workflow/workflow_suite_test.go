package workflow_test

import (
	"context"
	"testing"
	"time"

	"github.com/go-logr/logr"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/syntasso/kratix/api/v1alpha1"
	"github.com/syntasso/kratix/lib/workflow"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
)

var (
	fakeK8sClient client.Client
	fakeCRD       *apiextensionsv1.CustomResourceDefinition
	ctx           = context.TODO()
	logger        logr.Logger
)

func TestManager(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Workflow Reconciler Suite")
}

var _ = BeforeSuite(func() {
	err := v1alpha1.AddToScheme(scheme.Scheme)
	Expect(err).NotTo(HaveOccurred())
	logf.SetLogger(zap.New(zap.WriteTo(GinkgoWriter), zap.UseDevMode(true)))
	workflow.SetMinimumPeriodBetweenCreatingPipelineResources(time.Nanosecond)
	//+kubebuilder:scaffold:scheme
})

var _ = BeforeEach(func() {
	fakeCRD = &apiextensionsv1.CustomResourceDefinition{
		TypeMeta: metav1.TypeMeta{
			Kind:       "CustomResourceDefinition",
			APIVersion: "v1",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name: "thekinds.mygroup.example",
		},
		Spec: apiextensionsv1.CustomResourceDefinitionSpec{
			Group: "mygroup.example",
			Names: apiextensionsv1.CustomResourceDefinitionNames{
				Plural:   "thekinds",
				Singular: "thekind",
				Kind:     "TheKind",
			},
			Versions: []apiextensionsv1.CustomResourceDefinitionVersion{{Name: "v1"}},
		},
	}

	uResource := &unstructured.Unstructured{}
	uResource.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   fakeCRD.Spec.Group,
		Version: fakeCRD.Spec.Versions[0].Name,
		Kind:    fakeCRD.Spec.Names.Kind,
	})

	fakeK8sClient = fake.NewClientBuilder().WithScheme(scheme.Scheme).WithStatusSubresource(
		&v1alpha1.Promise{},
		uResource,
	).Build()
	logger = ctrl.Log.WithName("manager")
})
