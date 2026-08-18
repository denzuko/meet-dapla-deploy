.PHONY: build test doc dist clean

## build — compile a static binary via ros dump executable
build:
	ros dump executable meet-dapla-deploy --output meet-dapla-deploy

## test — run the e2e suite against a live deployment
test:
	./meet-dapla-deploy.ros e2e

## doc — generate HTML documentation via docs.ros
doc:
	ros docs.ros

## dist — package the binary for distribution
dist: build
	tar czf meet-dapla-deploy.tar.gz meet-dapla-deploy

## clean — remove build artifacts
clean:
	rm -f meet-dapla-deploy meet-dapla-deploy.tar.gz
