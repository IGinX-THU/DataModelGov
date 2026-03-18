from setuptools import setup, find_packages

setup(
    name="datamodelgov-sdk-python",
    version="1.0.0",
    description="DataModelGov Thrift RPC Client SDK for Python",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    author="Tsinghua University",
    author_email="contact@tsinghua.edu.cn",
    url="https://github.com/tsinghua/datamodelgov",
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    python_requires=">=3.8",
    install_requires=[
        "thrift==0.22.0",
    ],
    extras_require={
        "dev": [
            "pytest>=6.0",
            "pytest-cov>=2.0",
            "black>=21.0",
            "flake8>=3.8",
        ]
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
    keywords="datamodelgov, thrift, rpc, sdk",
    project_urls={
        "Bug Reports": "https://github.com/tsinghua/datamodelgov/issues",
        "Source": "https://github.com/tsinghua/datamodelgov",
        "Documentation": "https://github.com/tsinghua/datamodelgov/docs",
    },
)
