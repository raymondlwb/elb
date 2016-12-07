from setuptools import setup, find_packages


setup(
    name='erulb_py',
    version='0.0.1',
    author='timfeirg',
    zip_safe=True,
    author_email='timfeirg@icloud.com',
    description='ELB 3 python client',
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'requests',
        'setuptools',
    ],
)
